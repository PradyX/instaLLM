import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/skills/domain/built_in_skills.dart';
import 'package:installm/features/skills/domain/skill.dart';

/// Versioned registry containing copied text bundles and the shipped skills
/// the user removed. Preserve the original before every rewrite, including
/// older or partial data that the decoder skips.
class SkillStore {
  SkillStore(this.file);
  final File file;
  static const currentVersion = 3;

  /// Every schema this build can read. A file written by a newer build stays
  /// untouched: the registry turns read-only instead of being rewritten from
  /// what this build happens to understand.
  static const List<int> readableVersions = [1, 2, currentVersion];
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
      if (version is! int || !readableVersions.contains(version)) {
        _readOnly = true;
        return SkillsSnapshot.empty;
      }
      final snapshot = SkillsSnapshot.fromJson(raw);
      _preserve =
          version != currentVersion ||
          raw['skills'] is! List ||
          jsonEncode(raw['skills']) !=
              jsonEncode(
                snapshot.customSkills.map((skill) => skill.toJson()).toList(),
              ) ||
          jsonEncode(raw['disabledBuiltInIds'] ?? []) !=
              jsonEncode(snapshot.disabledBuiltInIds) ||
          jsonEncode(raw['removedBuiltInIds'] ?? []) !=
              jsonEncode(snapshot.removedBuiltInIds) ||
          raw.keys.any(
            (key) => !const {
              'version',
              'skills',
              'disabledBuiltInIds',
              'removedBuiltInIds',
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
          'removedBuiltInIds': snapshot.removedBuiltInIds,
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

/// Custom skills, which built-ins the user turned off, and which built-ins the
/// user removed from the list; built-ins are prepended by [allSkills].
class SkillsSnapshot {
  const SkillsSnapshot({
    required this.customSkills,
    this.disabledBuiltInIds = const [],
    this.removedBuiltInIds = const [],
  });

  static const SkillsSnapshot empty = SkillsSnapshot(customSkills: []);

  final List<Skill> customSkills;

  /// Built-in ids disabled by the user.
  final List<String> disabledBuiltInIds;

  /// Built-in ids the user removed. A built-in is code, so removing it takes
  /// it out of the registry rather than deleting anything; [removedBuiltInSkills]
  /// is what a restore offers back.
  final List<String> removedBuiltInIds;

  /// The shipped skills the user removed, in the order the app ships them.
  List<Skill> get removedBuiltInSkills => [
    for (final skill in BuiltInSkills.all())
      if (removedBuiltInIds.contains(skill.id)) skill,
  ];

  /// Built-ins that are still listed (with stored disables applied), followed
  /// by custom skills.
  List<Skill> get allSkills => [
    for (final skill in BuiltInSkills.all())
      if (!removedBuiltInIds.contains(skill.id))
        disabledBuiltInIds.contains(skill.id)
            ? skill.copyWith(enabled: false)
            : skill,
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
      removedBuiltInIds: removedBuiltInIds,
    );
  }

  SkillsSnapshot remove(String skillId) {
    return SkillsSnapshot(
      customSkills: customSkills.where((skill) => skill.id != skillId).toList(),
      disabledBuiltInIds: disabledBuiltInIds,
      removedBuiltInIds: removedBuiltInIds,
    );
  }

  /// Takes a built-in out of the list. Its disabled flag goes with it: a skill
  /// that is not listed has no switch to remember.
  SkillsSnapshot removeBuiltIn(String skillId) {
    return SkillsSnapshot(
      customSkills: customSkills,
      disabledBuiltInIds: disabledBuiltInIds
          .where((id) => id != skillId)
          .toList(),
      removedBuiltInIds: [
        ...removedBuiltInIds.where((id) => id != skillId),
        skillId,
      ],
    );
  }

  /// Puts a removed built-in back, enabled.
  SkillsSnapshot restoreBuiltIn(String skillId) {
    return SkillsSnapshot(
      customSkills: customSkills,
      disabledBuiltInIds: disabledBuiltInIds,
      removedBuiltInIds: removedBuiltInIds
          .where((id) => id != skillId)
          .toList(),
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
      removedBuiltInIds: removedBuiltInIds,
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
      removedBuiltInIds: readIds(json['removedBuiltInIds']),
    );
  }
}
