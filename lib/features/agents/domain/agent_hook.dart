import 'package:installm/features/tools/domain/tool_definition.dart';

/// Where in a run's life a hook is asked (Road Map 3 Phase 3.3.2).
///
/// Only [beforeTool] is enforced by this build; the other lifecycle points the
/// phase names (after-edit steps, on-input-needed) arrive as their own unit,
/// and a stored hook with a trigger this build does not enforce is kept in the
/// file rather than quietly acted on or dropped.
enum HookTrigger {
  /// Before a tool call runs, so a rule can refuse or question it.
  beforeTool('beforeTool', 'Before a tool runs');

  const HookTrigger(this.id, this.label);

  /// Stable id in the stored file; never localized.
  final String id;

  /// What the settings page shows.
  final String label;

  static HookTrigger? byId(String? id) {
    for (final trigger in HookTrigger.values) {
      if (trigger.id == id) return trigger;
    }
    return null;
  }
}

/// What a matching hook does to the call it matched.
///
/// There is deliberately no "allow": a hook is a guardrail, so it may only
/// refuse a call or force the permission question. Nothing in a hook file can
/// grant something the permission gate would have refused.
enum HookLevel {
  refuse('refuse', 'Refuse'),
  ask('ask', 'Ask first');

  const HookLevel(this.id, this.label);

  final String id;
  final String label;

  static HookLevel? byId(String? id) {
    for (final level in HookLevel.values) {
      if (level.id == id) return level;
    }
    return null;
  }
}

/// Limits that keep a hand-edited hook file from breaking every tool call.
abstract final class HookLimits {
  static const int maxNameCharacters = 80;
  static const int maxPatternCharacters = 200;
}

/// One user-defined rule attached to a lifecycle point.
///
/// A rule matches on the tool's name and, when the tool declares which
/// argument names the file or folder it acts on, on that path. It is listed,
/// editable and logged: a refusal is reported to the model and stored with the
/// tool activity of the turn, so no hook runs hidden.
class AgentHook {
  const AgentHook({
    required this.id,
    required this.name,
    this.enabled = true,
    this.trigger = HookTrigger.beforeTool,
    this.toolPattern = '*',
    this.resourcePattern = '',
    this.level = HookLevel.refuse,
    this.builtIn = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentHook.create({
    String? id,
    required String name,
    String toolPattern = '*',
    String resourcePattern = '',
    HookLevel level = HookLevel.refuse,
    HookTrigger trigger = HookTrigger.beforeTool,
    bool enabled = true,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return AgentHook(
      id: id ?? 'hook-${timestamp.microsecondsSinceEpoch}',
      name: name,
      enabled: enabled,
      trigger: trigger,
      toolPattern: toolPattern,
      resourcePattern: resourcePattern,
      level: level,
      createdAt: timestamp,
      updatedAt: timestamp,
    ).normalized();
  }

  final String id;
  final String name;
  final bool enabled;
  final HookTrigger trigger;

  /// Tool name the rule applies to: `*` for every tool, or a pattern where
  /// `*` stands for any run of characters (`vault_*`).
  final String toolPattern;

  /// Path pattern the rule applies to, matched against the resource a tool
  /// declares (for example the note path `vault_write_note` is given). Empty
  /// means the rule matches whatever the tool acts on. `*` stays inside one
  /// path segment and `**` crosses segments, so `Projects/**` protects a whole
  /// folder and `**/*.env` does not depend on how deep the file sits.
  final String resourcePattern;

  final HookLevel level;

  /// True for a rule that ships with the app rather than one the user wrote.
  ///
  /// A built-in floor is never stored, edited or deleted — it is the same in
  /// every install — and it can only restrict, so it cannot widen what the
  /// permission gate refused.
  final bool builtIn;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// True when this rule is about a path rather than a whole tool.
  bool get protectsPath => resourcePattern.trim().isNotEmpty;

  AgentHook normalized() {
    String clamp(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);
    final tool = toolPattern.trim();
    return AgentHook(
      id: id,
      name: clamp(name.trim(), HookLimits.maxNameCharacters),
      enabled: enabled,
      trigger: trigger,
      toolPattern: clamp(
        tool.isEmpty ? '*' : tool,
        HookLimits.maxPatternCharacters,
      ),
      resourcePattern: clamp(
        resourcePattern.trim(),
        HookLimits.maxPatternCharacters,
      ),
      level: level,
      builtIn: builtIn,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  AgentHook copyWith({
    String? name,
    bool? enabled,
    HookTrigger? trigger,
    String? toolPattern,
    String? resourcePattern,
    HookLevel? level,
    DateTime? updatedAt,
  }) {
    return AgentHook(
      id: id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      trigger: trigger ?? this.trigger,
      toolPattern: toolPattern ?? this.toolPattern,
      resourcePattern: resourcePattern ?? this.resourcePattern,
      level: level ?? this.level,
      builtIn: builtIn,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    ).normalized();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'enabled': enabled,
      'trigger': trigger.id,
      'toolPattern': toolPattern,
      'resourcePattern': resourcePattern,
      'level': level.id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Reads one stored hook. Null when the entry cannot be a hook of this
  /// build — a missing id or name, or a trigger this build does not enforce —
  /// so the store can keep the original file instead of rewriting it away.
  ///
  /// `builtIn` is never read from the file: a rule that ships with the app
  /// cannot be smuggled in as one the user may not delete.
  static AgentHook? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final trigger =
        HookTrigger.byId(json['trigger'] as String?) ?? HookTrigger.beforeTool;
    final level = HookLevel.byId(json['level'] as String?) ?? HookLevel.refuse;
    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return AgentHook(
      id: id,
      name: name,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      trigger: trigger,
      toolPattern: json['toolPattern'] is String
          ? json['toolPattern'] as String
          : '*',
      resourcePattern: json['resourcePattern'] is String
          ? json['resourcePattern'] as String
          : '',
      level: level,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    ).normalized();
  }
}

/// The guardrails that ship with the app, evaluated before any user rule.
///
/// They exist so an agent cannot write into the parts of a folder that are not
/// the user's work to hand over — git's own bookkeeping — even before the user
/// has written a rule of their own. They are read-only here (never stored,
/// edited or deleted) because a floor a later run could switch off would not be
/// a floor.
abstract final class BuiltInHooks {
  /// Sentinel times: a built-in was not created by a person at a moment.
  static final DateTime _notCreated = DateTime.fromMillisecondsSinceEpoch(0);

  static final List<AgentHook> all = [
    AgentHook(
      id: 'builtin-git-internals',
      name: 'Git internals',
      toolPattern: '*',
      resourcePattern: '**/.git/**',
      level: HookLevel.refuse,
      builtIn: true,
      createdAt: _notCreated,
      updatedAt: _notCreated,
    ),
  ];
}

/// The rule a call matched, with the resource the match was made against.
class HookMatch {
  const HookMatch({required this.hook, this.resource});

  final AgentHook hook;
  final String? resource;

  /// Why the call was refused, in words the model can act on and the user can
  /// trace back to the rule that decided it.
  String get refusalMessage {
    final target = resource == null || resource!.isEmpty
        ? 'this tool'
        : '“${resource!}”';
    return 'The hook “${hook.name}” refused to let this call touch $target, '
        'so nothing ran. The user can change this in Settings › Hooks.';
  }

  /// Why the permission question was asked.
  String get askedMessage =>
      'The hook “${hook.name}” asks before a call like this runs.';
}

/// The hooks in force, and the one place a tool call is matched against them.
class HookPolicy {
  const HookPolicy({this.hooks = const []});

  final List<AgentHook> hooks;

  /// The strictest enabled rule that matches this call, or null.
  ///
  /// Every rule is considered and the strictest one decides, so the order of
  /// the file can never make a refusal weaker: a rule the user wrote still
  /// refuses what the built-in floor would only have questioned, and nothing
  /// in a hook file can turn a refusal back into a run. The first rule at the
  /// strictest level wins, which is what makes the list readable.
  HookMatch? matchFor({
    required ToolDefinition tool,
    required Map<String, Object?> arguments,
  }) {
    if (hooks.isEmpty) return null;
    final resource = resourceFor(tool, arguments);
    HookMatch? best;
    for (final hook in hooks) {
      if (!hook.enabled || hook.trigger != HookTrigger.beforeTool) continue;
      if (!matchesToolPattern(hook.toolPattern, tool.name)) continue;
      if (hook.protectsPath) {
        if (resource == null || resource.isEmpty) continue;
        if (!matchesPathPattern(hook.resourcePattern, resource)) continue;
      }
      if (best == null || _stricter(hook.level, best.hook.level)) {
        best = HookMatch(hook: hook, resource: resource);
      }
    }
    return best;
  }

  /// Refusing outranks asking, so a match is only replaced by a stricter one.
  static bool _stricter(HookLevel candidate, HookLevel current) =>
      candidate == HookLevel.refuse && current != HookLevel.refuse;

  /// The file or folder a call acts on, from the arguments the tool declares
  /// as naming it. Null when the tool declares none or the call leaves them
  /// out, which is why a path rule never matches a tool that cannot say what
  /// it touches.
  static String? resourceFor(
    ToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    for (final name in tool.resourceArguments) {
      final value = arguments[name];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}

/// True when [pattern] matches the tool [name]. Empty never matches, so a
/// half-written rule is inert rather than universal.
bool matchesToolPattern(String pattern, String name) {
  final trimmed = pattern.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed == '*') return true;
  return _compile(trimmed, path: false).hasMatch(name);
}

/// True when [pattern] matches the path [value], with `*` staying inside one
/// segment and `**` crossing them.
bool matchesPathPattern(String pattern, String value) {
  final trimmed = pattern.trim();
  if (trimmed.isEmpty) return false;
  // A folder pattern covers the folder itself as well as its contents, so
  // `Projects/**` matches `Projects` too.
  final normalized = value.replaceAll('\\', '/');
  if (trimmed.endsWith('/**')) {
    final folder = trimmed.substring(0, trimmed.length - 3);
    if (normalized == folder) return true;
    // `**/name/**` also covers a path that is just `name`, so the folder
    // itself is protected and not only what sits inside it.
    if (folder.startsWith('**/') && normalized == folder.substring(3)) {
      return true;
    }
  }
  return _compile(trimmed, path: true).hasMatch(normalized);
}

/// Compiles a `*`/`**` pattern. Path patterns keep `*` within one segment;
/// tool patterns treat it as any run of characters.
RegExp _compile(String pattern, {required bool path}) {
  final buffer = StringBuffer('^');
  for (var index = 0; index < pattern.length; index++) {
    final char = pattern[index];
    if (char == '*') {
      final doubleStar =
          index + 1 < pattern.length && pattern[index + 1] == '*';
      if (doubleStar) {
        index++;
        final folder = index + 1 < pattern.length && pattern[index + 1] == '/';
        if (folder) index++;
        buffer.write(folder ? r'(?:.*/)?' : '.*');
      } else {
        buffer.write(path ? r'[^/]*' : '.*');
      }
      continue;
    }
    if (r'\^$.|?+()[]{}'.contains(char)) {
      buffer.write('\\$char');
    } else {
      buffer.write(char);
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}
