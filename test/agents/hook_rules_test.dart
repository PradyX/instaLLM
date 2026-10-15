import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/domain/agent_hook.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

ToolDefinition _tool(String name, {List<String> resources = const []}) =>
    ToolDefinition(
      name: name,
      description: 'Test tool $name.',
      parameters: const [],
      risk: ToolRiskLevel.sensitive,
      resourceArguments: resources,
    );

AgentHook _rule({
  String id = 'r1',
  String name = 'Rule',
  String toolPattern = '*',
  String resourcePattern = '',
  HookLevel level = HookLevel.refuse,
  bool enabled = true,
}) => AgentHook.create(
  id: id,
  name: name,
  toolPattern: toolPattern,
  resourcePattern: resourcePattern,
  level: level,
  enabled: enabled,
);

HookMatch? _match(
  List<AgentHook> hooks,
  ToolDefinition tool,
  Map<String, Object?> arguments,
) => HookPolicy(hooks: hooks).matchFor(tool: tool, arguments: arguments);

void main() {
  group('path patterns', () {
    test('a folder pattern covers the folder and everything inside it', () {
      expect(matchesPathPattern('Projects/**', 'Projects'), isTrue);
      expect(matchesPathPattern('Projects/**', 'Projects/notes/a.md'), isTrue);
      expect(matchesPathPattern('Projects/**', 'Other/a.md'), isFalse);
      expect(matchesPathPattern('**/secrets/**', 'secrets'), isTrue);
      expect(matchesPathPattern('**/secrets/**', 'a/b/secrets/x.md'), isTrue);
      expect(matchesPathPattern('**/secrets/**', 'a/b/secretsx/x.md'), isFalse);
    });

    test('one star stays inside a segment while two cross them', () {
      expect(matchesPathPattern('secrets/*', 'secrets/key.md'), isTrue);
      expect(matchesPathPattern('secrets/*', 'secrets/deep/key.md'), isFalse);
      expect(matchesPathPattern('**/*.env', '.env'), isTrue);
      expect(matchesPathPattern('**/*.env', 'a/b/prod.env'), isTrue);
      expect(matchesPathPattern('**/*.env', 'a/b/environment'), isFalse);
    });

    test('a half-written pattern is inert rather than universal', () {
      expect(matchesPathPattern('', 'anything'), isFalse);
      expect(matchesPathPattern('   ', 'anything'), isFalse);
      expect(matchesToolPattern('', 'calculator'), isFalse);
      expect(matchesToolPattern('*', 'calculator'), isTrue);
    });
  });

  group('policy', () {
    final writeNote = _tool(
      'vault_write_note',
      resources: const ['relativePath'],
    );

    test('refuses a call whose path a rule protects', () {
      final match = _match(
        [_rule(name: 'Protect secrets', resourcePattern: 'secrets/**')],
        writeNote,
        {'relativePath': 'secrets/keys.md'},
      );

      expect(match, isNotNull);
      expect(match!.hook.name, 'Protect secrets');
      expect(match.resource, 'secrets/keys.md');
      expect(match.refusalMessage, contains('Protect secrets'));
      expect(match.refusalMessage, contains('secrets/keys.md'));
    });

    test('leaves an unprotected path alone', () {
      final match = _match(
        [_rule(name: 'Protect secrets', resourcePattern: 'secrets/**')],
        writeNote,
        {'relativePath': 'notes/ok.md'},
      );

      expect(match, isNull);
    });

    test('a path rule never matches a tool that names no resource', () {
      final match = _match(
        [_rule(resourcePattern: '**/*')],
        _tool('calculator'),
        {'expression': '1+1'},
      );

      expect(match, isNull);
    });

    test('a path rule never matches a call that leaves the path out', () {
      final match = _match(
        [_rule(resourcePattern: '**/*')],
        writeNote,
        const {},
      );

      expect(match, isNull);
    });

    test('a disabled rule is not a rule', () {
      final match = _match(
        [_rule(resourcePattern: '**/*', enabled: false)],
        writeNote,
        {'relativePath': 'notes/ok.md'},
      );

      expect(match, isNull);
    });

    test('a tool rule matches by name pattern', () {
      final match = _match(
        [_rule(toolPattern: 'vault_*')],
        writeNote,
        {'relativePath': 'notes/ok.md'},
      );

      expect(match, isNotNull);
      expect(
        _match([_rule(toolPattern: 'shell_*')], writeNote, const {}),
        isNull,
      );
    });

    test('the strictest match wins whichever order the file has', () {
      final asked = _rule(
        id: 'ask',
        name: 'Ask about notes',
        resourcePattern: 'notes/**',
        level: HookLevel.ask,
      );
      final refused = _rule(
        id: 'refuse',
        name: 'Refuse notes',
        resourcePattern: 'notes/**',
      );

      for (final hooks in [
        [asked, refused],
        [refused, asked],
      ]) {
        final match = _match(hooks, writeNote, {'relativePath': 'notes/a.md'});
        expect(match!.hook.level, HookLevel.refuse);
        expect(match.hook.name, 'Refuse notes');
      }
    });

    test('the built-in floor refuses git internals', () {
      final match = _match(BuiltInHooks.all, writeNote, {
        'relativePath': 'Project/.git/config.md',
      });

      expect(match, isNotNull);
      expect(match!.hook.builtIn, isTrue);
      expect(match.hook.level, HookLevel.refuse);
      expect(match.refusalMessage, contains('Git internals'));
    });

    test('no rule can widen the built-in floor back into a run', () {
      final match = _match(
        [
          ...BuiltInHooks.all,
          _rule(
            id: 'mine',
            name: 'Notes are fine',
            resourcePattern: '**',
            level: HookLevel.ask,
          ),
        ],
        writeNote,
        {'relativePath': '.git/config.md'},
      );

      expect(match!.hook.builtIn, isTrue);
      expect(match.hook.level, HookLevel.refuse);
    });
  });
}
