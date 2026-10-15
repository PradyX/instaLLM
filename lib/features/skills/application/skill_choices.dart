import 'package:installm/features/skills/application/skill_session.dart';
import 'package:installm/features/skills/domain/skill_selector.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/core/permissions/workspace_permission.dart';
import 'package:installm/i18n/strings.g.dart';

/// Separate versioned session preferences preserve model-independent history.
/// No existing conversation or room document needs rewriting.
class SkillChoice {
  const SkillChoice(this.skillId, [this.resources = const []]);
  final String skillId;
  final List<String> resources;
  Map<String, Object> toJson() => {'skillId': skillId, 'resources': resources};
  static SkillChoice? fromJson(Object? raw) {
    if (raw is! Map ||
        raw['skillId'] is! String ||
        (raw['skillId'] as String).isEmpty) {
      return null;
    }
    if (raw['resources'] != null &&
        (raw['resources'] is! List ||
            (raw['resources'] as List).any((v) => v is! String))) {
      return null;
    }
    return SkillChoice(
      raw['skillId'] as String,
      (raw['resources'] as List? ?? []).cast<String>(),
    );
  }
}

class SkillChoiceStore {
  SkillChoiceStore(this.file);
  final File file;
  bool readOnly = false;
  bool _preserve = false;
  Map<String, SkillChoice> load() {
    if (!file.existsSync()) return {};
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) {
        _preserve = true;
        return {};
      }
      if (raw['version'] != 1) {
        readOnly = true;
        return {};
      }
      if (raw['choices'] is! Map) {
        _preserve = true;
        return {};
      }
      _preserve =
          _preserve ||
          raw.keys.any((key) => !const {'version', 'choices'}.contains(key));
      final result = <String, SkillChoice>{};
      for (final entry in (raw['choices'] as Map).entries) {
        final choice = SkillChoice.fromJson(entry.value);
        if (entry.value is Map &&
            (entry.value as Map).keys.any(
              (key) => !const {'skillId', 'resources'}.contains(key),
            )) {
          _preserve = true;
        }
        if (entry.key is String && choice != null) {
          result[entry.key as String] = choice;
        } else {
          _preserve = true;
        }
      }
      return result;
    } on FormatException {
      _preserve = true;
      return {};
    }
  }

  bool save(Map<String, SkillChoice> choices) {
    final temporary = File('${file.path}.tmp');
    try {
      load();
      if (readOnly) return false;
      if (_preserve && file.existsSync()) {
        file.copySync(
          '${file.path}.preserved-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      file.parent.createSync(recursive: true);
      temporary.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'choices': choices.map((key, value) => MapEntry(key, value.toJson())),
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

final skillChoiceStoreProvider = FutureProvider<SkillChoiceStore>(
  (ref) async => SkillChoiceStore(
    File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'skills',
        'choices.json',
      ),
    ),
  ),
);
final skillChoicesProvider =
    StateNotifierProvider<SkillChoicesNotifier, Map<String, SkillChoice>>(
      (ref) => SkillChoicesNotifier(ref),
    );

class SkillChoicesNotifier extends StateNotifier<Map<String, SkillChoice>> {
  SkillChoicesNotifier(this.ref) : super({}) {
    whenReady = _load();
  }
  final Ref ref;
  late final Future<void> whenReady;
  Future<void> _load() async {
    try {
      final store = await ref.read(skillChoiceStoreProvider.future);
      if (mounted) state = store.load();
    } catch (_) {}
  }

  Future<bool> select(String key, SkillChoice? choice) async {
    await whenReady;
    try {
      final store = await ref.read(skillChoiceStoreProvider.future);
      final next = {...state};
      if (choice == null) {
        next.remove(key);
      } else {
        next[key] = choice;
      }
      if (!store.save(next)) return false;
      if (mounted) state = next;
      return true;
    } catch (_) {
      return false;
    }
  }
}

bool eligibleSkill(
  Skill skill, {
  String? workspaceId,
  String? botId,
  Set<String> capabilities = const {'filesystem:read'},
  List<String>? assignedSkillIds,
}) {
  return skill.enabled &&
      (skill.workspaceId == null || skill.workspaceId == workspaceId) &&
      (skill.assignedBotIds.isEmpty ||
          (botId != null && skill.assignedBotIds.contains(botId))) &&
      (assignedSkillIds == null || assignedSkillIds.contains(skill.id)) &&
      skill.allowedFor(capabilities.map(Capability.new).toSet());
}

class SkillCommand {
  const SkillCommand({
    this.choice,
    this.clear = false,
    this.message,
    this.task = '',
  });
  final SkillChoice? choice;
  final bool clear;
  final String? message;
  final String task;

  static String nameFor(Skill skill) => skill.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  static SkillCommand? parse(String text, List<Skill> eligible) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('/')) return null;
    final split = trimmed.indexOf(RegExp(r'\s'));
    final name = trimmed
        .substring(1, split < 0 ? trimmed.length : split)
        .toLowerCase();
    var task = split < 0 ? '' : trimmed.substring(split).trim();
    if (name.isEmpty || name == 'skills') {
      final counts = <String, int>{};
      for (final skill in eligible) {
        counts.update(nameFor(skill), (v) => v + 1, ifAbsent: () => 1);
      }
      return SkillCommand(
        message:
            '${t.skills.commands}\n/chat — ${t.skills.normalChat}\n${eligible.map((skill) => '/${nameFor(skill)}${(counts[nameFor(skill)]! > 1 || const {'chat', 'skills'}.contains(nameFor(skill))) ? '@${skill.id}' : ''} — ${skill.description.isEmpty ? skill.name : skill.description}').join('\n')}',
      );
    }
    if (name == 'chat') {
      return SkillCommand(
        clear: true,
        message: task.isEmpty ? t.skills.normalChat : null,
        task: task,
      );
    }
    final matches = eligible
        .where(
          (skill) =>
              name == '${nameFor(skill)}@${skill.id}'.toLowerCase() ||
              name == nameFor(skill),
        )
        .toList();
    if (matches.length != 1) {
      return SkillCommand(
        message: matches.isEmpty ? t.skills.unavailable : t.skills.ambiguous,
      );
    }
    final skill = matches.single;
    final resources = <String>[];
    while (task.startsWith('--resource=')) {
      final end = task.indexOf(RegExp(r'\s'));
      final path = task.substring(11, end < 0 ? task.length : end);
      if (!skill.resourceNames.contains(path) || resources.length >= 8) {
        return SkillCommand(message: t.skills.resourceUnavailable);
      }
      resources.add(path);
      task = end < 0 ? '' : task.substring(end).trim();
    }
    return SkillCommand(
      choice: SkillChoice(skill.id, resources.toSet().toList()),
      task: task,
      message: task.isEmpty ? t.skills.selected(name: skill.name) : null,
    );
  }
}

SkillSession? choiceSession({
  required SkillChoice? choice,
  required List<Skill> eligible,
  required int usableInputTokens,
  required bool Function(Skill) isCurrent,
}) {
  if (choice == null) return null;
  final matches = eligible.where((skill) => skill.id == choice.skillId);
  if (matches.isEmpty) throw FormatException(t.skills.unavailable);
  final selected = SkillSelector.select(
    ranked: [matches.single],
    usableInputTokens: usableInputTokens,
  );
  if (selected.isEmpty) throw FormatException(t.skills.budgetError);
  final session = SkillSession(
    skills: [matches.single],
    tokenBudget: usableInputTokens ~/ SkillSelector.maximumSkillShare,
    isCurrent: isCurrent,
  );
  for (final path in choice.resources) {
    final result = session.readResource(matches.single.id, path);
    if (!result.startsWith('Skill resource ')) throw FormatException(result);
  }
  return session;
}
