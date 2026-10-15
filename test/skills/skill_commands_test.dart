import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/skills/application/skill_usage.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/skills/application/skill_choices.dart';
import 'package:installm/features/skills/domain/skill.dart';
import 'package:installm/features/skills/domain/built_in_skills.dart';
import 'package:installm/features/skills/data/skill_store.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import '../memory/memory_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'commands list eligible choices, explicitly select review and clear',
    () {
      final skills = BuiltInSkills.all();
      expect(SkillCommand.parse('ordinary text', skills), isNull);
      expect(SkillCommand.parse('/', skills)!.message, contains('/review'));
      final review = SkillCommand.parse('/review inspect this patch', skills)!;
      expect(review.choice!.skillId, 'skill-builtin-review');
      expect(review.task, 'inspect this patch');
      expect(SkillCommand.parse('/chat', skills)!.clear, isTrue);
      expect(
        SkillCommand.parse('/missing', skills)!.message,
        contains('unavailable'),
      );
    },
  );
  test(
    'ambiguous names need the full listed command and templates are explicit',
    () {
      final one = Skill.create(
        id: 'one',
        name: 'docs',
        resourceNames: ['templates/a.md'],
      );
      final two = Skill.create(id: 'two', name: 'docs');
      expect(
        SkillCommand.parse('/docs', [one, two])!.message,
        contains('More than one'),
      );
      expect(
        SkillCommand.parse('/', [one, two])!.message,
        contains('/docs@one'),
      );
      final command = SkillCommand.parse(
        '/docs@one --resource=templates/a.md write a report',
        [one, two],
      )!;
      expect(command.choice!.resources, ['templates/a.md']);
      expect(command.task, 'write a report');
      expect(
        SkillCommand.parse('/docs@one --resource=../secret task', [
          one,
          two,
        ])!.choice,
        isNull,
      );
    },
  );
  test(
    'assignment/workspace/capability boundaries apply to explicit choices',
    () {
      final skill = Skill.create(
        name: 'private',
        workspaceId: 'w',
        assignedBotIds: ['one'],
        requiredCapabilities: {'shell.execute'},
      );
      expect(eligibleSkill(skill, workspaceId: 'w'), isFalse);
      expect(
        eligibleSkill(
          skill,
          workspaceId: 'w',
          botId: 'one',
          capabilities: {'shell.execute'},
          assignedSkillIds: [skill.id],
        ),
        isTrue,
      );
      expect(
        eligibleSkill(
          skill,
          botId: 'one',
          capabilities: {'shell.execute'},
          assignedSkillIds: [skill.id],
        ),
        isFalse,
      );
      expect(
        eligibleSkill(
          skill,
          workspaceId: 'w',
          botId: 'one',
          capabilities: {'shell.execute'},
          assignedSkillIds: [],
        ),
        isFalse,
      );
      expect(
        eligibleSkill(
          skill.copyWith(enabled: false),
          workspaceId: 'w',
          botId: 'one',
          capabilities: {'shell.execute'},
          assignedSkillIds: [skill.id],
        ),
        isFalse,
      );
    },
  );
  test(
    'choice store round-trips and preserves partial/corrupt/future documents',
    () {
      final root = Directory.systemTemp.createTempSync('skill-choices-');
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File('${root.path}/choices.json');
      final store = SkillChoiceStore(file);
      expect(
        store.save({
          'conversation:c': const SkillChoice('s', ['templates/a.md']),
        }),
        isTrue,
      );
      expect(SkillChoiceStore(file).load()['conversation:c']!.resources, [
        'templates/a.md',
      ]);
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'choices': {
            'keep': {'skillId': 's'},
            'partial': 42,
          },
        }),
      );
      final original = file.readAsStringSync();
      expect(store.save(store.load()), isTrue);
      expect(
        root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('preserved'))
            .single
            .readAsStringSync(),
        original,
      );
      file.writeAsStringSync('broken');
      expect(store.save(store.load()), isTrue);
      file.writeAsStringSync('{"version":99}');
      expect(store.save({}), isFalse);
      expect(file.readAsStringSync(), '{"version":99}');
    },
  );
  test(
    'explicit resources share the body budget and overflow is actionable',
    () {
      final skill = Skill.create(
        id: 's',
        name: 'docs',
        body: 'Instructions',
        resourceNames: ['templates/a.md'],
        bundleFiles: {'templates/a.md': 'Template words'},
      );
      final session = choiceSession(
        choice: const SkillChoice('s', ['templates/a.md']),
        eligible: [skill],
        usableInputTokens: 4000,
        isCurrent: (_) => true,
      )!;
      expect(session.resourceSections.single, contains('Template words'));
      expect(session.usedTokens, lessThanOrEqualTo(1000));
      expect(
        () => choiceSession(
          choice: const SkillChoice('s'),
          eligible: [skill.copyWith(body: 'long ' * 2000)],
          usableInputTokens: 256,
          isCurrent: (_) => true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'Home listing and selection need no model and persist independently of model choice',
    () async {
      final harness = MemoryTestHarness();
      addTearDown(harness.close);
      final container = harness.container();
      final home = await harness.home(container);
      await home.sendMessage('/');
      expect(
        container.read(homeControllerProvider).last.content,
        contains('/review'),
      );
      expect(harness.engine.prompts, isEmpty);
      await home.sendMessage('/review');
      final id = container
          .read(conversationControllerProvider)
          .activeConversationId!;
      final store = await container.read(skillChoiceStoreProvider.future);
      expect(
        SkillChoiceStore(store.file).load()['conversation:$id']!.skillId,
        'skill-builtin-review',
      );
      await home.sendMessage('/chat');
      expect(store.load().containsKey('conversation:$id'), isFalse);
      expect(harness.engine.prompts, isEmpty);
    },
  );
  test(
    'Home model-requested resource reaches the follow-up and its actual inspector',
    () async {
      final engine = _ResourceEngine();
      final harness = MemoryTestHarness(
        engine: engine,
        registry: ToolRegistry(tools: [], platform: ToolPlatform.linux),
        models: const [
          LlmModel(
            id: 'm1',
            name: 'One',
            parameterSize: '1B',
            description: 'test',
            isDownloaded: true,
            capabilities: [ModelCapability.tools],
          ),
        ],
      );
      addTearDown(harness.close);
      final skill = Skill.create(
        id: 'docs',
        name: 'reports',
        body: 'Preserve the report instructions.',
        resourceNames: ['references/report.md'],
        bundleFiles: {
          'references/report.md': 'Unique reference evidence for this run.',
        },
      );
      SkillStore(
        File('${harness.root.path}/skills/skills.json'),
      ).save(SkillsSnapshot(customSkills: [skill]));
      final container = harness.container();
      final records = <SkillUsage>[];
      container.listen(
        skillUsageProvider,
        (_, next) => records.addAll(next.values),
      );
      final home = await harness.home(container);
      await home.sendMessage('/reports Use the declared report reference.');
      expect(engine.prompts, hasLength(2));
      expect(
        engine.prompts.first,
        isNot(contains('Unique reference evidence for this run.')),
      );
      expect(
        engine.prompts.last,
        contains('Unique reference evidence for this run.'),
      );
      expect(
        engine.prompts.last,
        contains('Preserve the report instructions.'),
      );
      expect(records.first.resources, 0);
      expect(records.last.resources, greaterThan(0));
      expect(
        records.last.skills + records.last.otherInput,
        records.last.inputTokens,
      );
      expect(
        records.last.inputTokens + records.last.reservedOutput,
        lessThanOrEqualTo(records.last.window),
      );
      expect(engine.reservations[0], engine.reservations[1]);
      expect(
        container.read(homeControllerProvider).last.content,
        contains('Used the reference'),
      );
    },
  );
  test(
    'Home real send path injects chosen instructions/templates across model switches',
    () async {
      final harness = MemoryTestHarness(
        models: const [
          LlmModel(
            id: 'm1',
            name: 'One',
            parameterSize: '1B',
            description: 'test',
            isDownloaded: true,
          ),
          LlmModel(
            id: 'm2',
            name: 'Two',
            parameterSize: '1B',
            description: 'test',
            isDownloaded: true,
          ),
        ],
      );
      addTearDown(harness.close);
      final skill = Skill.create(
        id: 'docs',
        name: 'reports',
        body: 'Always use the requested report structure.',
        resourceNames: ['templates/report.md'],
        bundleFiles: {'templates/report.md': '# Evidence\n# Validation'},
      );
      SkillStore(
        File('${harness.root.path}/skills/skills.json'),
      ).save(SkillsSnapshot(customSkills: [skill]));
      final container = harness.container();
      final home = await harness.home(container);
      await home.sendMessage(
        '/reports --resource=templates/report.md report the result',
      );
      expect(
        harness.engine.prompts.last,
        contains('Always use the requested report structure.'),
      );
      expect(harness.engine.prompts.last, contains('# Evidence'));
      final id = container
          .read(conversationControllerProvider)
          .activeConversationId!;
      final usage = container.read(skillUsageProvider)['conversation:$id']!;
      expect(usage.instructions, greaterThan(0));
      expect(usage.resources, greaterThan(0));
      expect(usage.skills + usage.otherInput, usage.inputTokens);
      final projected = container.read(homeContextProjectionProvider)!;
      expect(projected.fixedTokens, greaterThan(usage.skills));
      expect(
        usage.inputTokens + usage.reservedOutput,
        lessThanOrEqualTo(usage.window),
      );
      (container.read(modelSelectionControllerProvider.notifier)
              as MemoryTestSelection)
          .choose('m2');
      await home.sendMessage('Add the next result');
      expect(harness.engine.prompts.last, contains('# Evidence'));
      expect(container.read(homeControllerProvider).last.modelId, 'm2');
      await home.sendMessage('/chat continue normally');
      // Earlier history may quote the command's task; the instruction prefix is gone.
      expect(
        harness.engine.prompts.last,
        isNot(contains('Always use the requested report structure.')),
      );
    },
  );
}

class _ResourceEngine extends MemoryTestEngine {
  @override
  Stream<String> generateResponse(String prompt, {int? maxTokens}) {
    prompts.add(prompt);
    reservations.add(maxTokens);
    return Stream.value(
      prompts.length == 1
          ? jsonEncode({
              'type': 'tool_call',
              'tool': 'skill_read_resource',
              'arguments': {'skillId': 'docs', 'path': 'references/report.md'},
            })
          : 'Used the reference.',
    );
  }
}
