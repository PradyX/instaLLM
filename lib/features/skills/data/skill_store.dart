import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/skills/domain/built_in_skills.dart';
import 'package:installm/features/skills/domain/skill.dart';

/// Versioned registry containing copied text bundles. Preserve the original
/// before every rewrite, including partial v1 data that the decoder skips.
class SkillStore {
  SkillStore(this.file);
  final File file;
  static const currentVersion = 2;
  bool _readOnly = false;
  bool _preserve = false;
  bool get isReadOnly => _readOnly;
  String get filePath => file.path;
  static Future<SkillStore> open() async => SkillStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'skills',
        'skills.json',
      ),
    ),
  );

  SkillsSnapshot load() {
    if (!file.existsSync()) return SkillsSnapshot.empty;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) {
        _preserve = true;
        return SkillsSnapshot.empty;
      }
      final version = raw['version'];
      if (version != 1 && version != currentVersion) {
        _readOnly = true;
        return SkillsSnapshot.empty;
      }
      final snapshot = SkillsSnapshot.fromJson(raw);
      _preserve =
          version == 1 ||
          raw['skills'] is! List ||
          jsonEncode(raw['skills']) !=
              jsonEncode(
                snapshot.customSkills.map((skill) => skill.toJson()).toList(),
              ) ||
          jsonEncode(raw['disabledBuiltInIds'] ?? []) !=
              jsonEncode(snapshot.disabledBuiltInIds) ||
          raw.keys.any(
            (key) => !const {
              'version',
              'skills',
              'disabledBuiltInIds',
            }.contains(key),
          );
      return snapshot;
    } on FormatException {
      _preserve = true;
      return SkillsSnapshot.empty;
    }
  }

  bool save(SkillsSnapshot snapshot) {
    final temporary = File('${file.path}.tmp');
    try {
      // Re-read so a future-version file introduced after load stays protected.
      load();
      if (_readOnly) return false;
      if (_preserve && file.existsSync()) {
        file.copySync(
          '${file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(
        jsonEncode({
          'version': currentVersion,
          'skills': snapshot.customSkills.map((s) => s.toJson()).toList(),
          'disabledBuiltInIds': snapshot.disabledBuiltInIds,
        }),
        flush: true,
      );
      temporary.renameSync(file.path);
      _preserve = false;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } catch (_) {}
      }
    }
  }
}

/// Custom skills plus which built-ins the user turned off; built-ins are
/// prepended by [allSkills].
class SkillsSnapshot {
  const SkillsSnapshot({
    required this.customSkills,
    this.disabledBuiltInIds = const [],
  });

  static const SkillsSnapshot empty = SkillsSnapshot(customSkills: []);

  final List<Skill> customSkills;

  /// Built-in ids disabled by the user.
  final List<String> disabledBuiltInIds;

  /// Built-ins (with stored disables applied) followed by custom skills.
  List<Skill> get allSkills => [
    for (final skill in BuiltInSkills.all())
      if (disabledBuiltInIds.contains(skill.id))
        skill.copyWith(enabled: false)
      else
        skill,
    ...customSkills,
  ];

  SkillsSnapshot upsert(Skill skill) {
    final updated = <Skill>[];
    var replaced = false;
    for (final existing in customSkills) {
      if (existing.id == skill.id) {
        updated.add(skill);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(skill);
    return SkillsSnapshot(
      customSkills: updated,
      disabledBuiltInIds: disabledBuiltInIds,
    );
  }

  SkillsSnapshot remove(String skillId) {
    return SkillsSnapshot(
      customSkills: customSkills.where((skill) => skill.id != skillId).toList(),
      disabledBuiltInIds: disabledBuiltInIds,
    );
  }

  /// Records a built-in enable/disable that survives restarts.
  SkillsSnapshot withBuiltInEnabled(String skillId, bool enabled) {
    final disabled = disabledBuiltInIds.toSet();
    if (enabled) {
      disabled.remove(skillId);
    } else {
      disabled.add(skillId);
    }
    return SkillsSnapshot(
      customSkills: customSkills,
      disabledBuiltInIds: disabled.toList(),
    );
  }

  static SkillsSnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['skills'];
    final skills = <Skill>[];
    if (raw is List) {
      for (final entry in raw) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        // Built-ins are code: a stored copy (from an older build) is ignored.
        if (map['source'] == SkillSource.builtIn.name) continue;
        final skill = Skill.fromJson(map);
        if (skill != null) skills.add(skill);
      }
    }
    List<String> readIds(Object? value) {
      if (value is! List) return const [];
      return value.whereType<String>().toList(growable: false);
    }

    return SkillsSnapshot(
      customSkills: skills,
      disabledBuiltInIds: readIds(json['disabledBuiltInIds']),
    );
  }
}
