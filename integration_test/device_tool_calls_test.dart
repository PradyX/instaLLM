import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/features/agents/application/agent_controller.dart';
import 'package:installm/features/agents/application/agent_loop_service.dart';
import 'package:installm/features/agents/domain/agent_run.dart';
import 'package:installm/features/context/application/context_budget_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/tools/application/tools_providers.dart';

/// One tool-call fixture: the sentence a user types, and what the model is
/// expected to do with it.
///
/// The expectation is deliberately loose. A model may spell an expression
/// differently and still be right, so a fixture names the tool it must reach,
/// the arguments that must be present, and any value an enumerated argument
/// must land on. Everything else is judged by the registry, which is the same
/// validator the app uses at runtime.
class ToolCallFixture {
  const ToolCallFixture({
    required this.prompt,
    required this.expectedTool,
    this.requiredArguments = const [],
    this.allowedValues = const {},
  });

  final String prompt;
  final String expectedTool;
  final List<String> requiredArguments;
  final Map<String, List<String>> allowedValues;
}

/// What one fixture produced, in the shape the report needs.
class ToolCallOutcome {
  const ToolCallOutcome({
    required this.fixture,
    required this.calledTool,
    required this.arguments,
    required this.status,
    required this.iterations,
    required this.toolCalls,
    required this.durationMs,
    required this.answer,
    required this.error,
  });

  final ToolCallFixture fixture;
  final String? calledTool;
  final String arguments;
  final String? status;
  final int iterations;
  final int toolCalls;
  final int durationMs;
  final String answer;
  final String? error;

  /// `pass`, `partial` or `fail`, decided the way a benchmark would read it.
  ///
  /// `pass` means the expected tool ran and its arguments validated. `partial`
  /// means the right tool was chosen but the arguments were rejected, which is
  /// the failure mode worth separating from a model that never calls a tool.
  String get verdict {
    if (error != null) return 'fail';
    if (calledTool == null) return 'fail';
    if (calledTool != fixture.expectedTool) return 'fail';
    if (status != 'Success') return 'partial';
    return 'pass';
  }
}

/// The prompts every run uses, in the order tools are tested.
///
/// Ordered from easiest to hardest: a single required number, a string with a
/// cap, an optional enumerated argument, a call with no arguments at all, and
/// one that has to carry a free-text query. A model that clears the first two
/// and fails the rest tells you something specific about its JSON habits.
const List<ToolCallFixture> toolCallFixtures = [
  ToolCallFixture(
    prompt:
        'What is 18% of 2450? Use the calculator tool, then answer in one '
        'sentence.',
    expectedTool: 'calculator',
    requiredArguments: ['expression'],
  ),
  ToolCallFixture(
    prompt:
        'Multiply 137 by 29. Use the calculator tool, then answer in one '
        'sentence.',
    expectedTool: 'calculator',
    requiredArguments: ['expression'],
  ),
  ToolCallFixture(
    prompt: 'What is the current date and time on this device? Use a tool.',
    expectedTool: 'current_datetime',
    allowedValues: {
      'timezone': ['local', 'utc'],
    },
  ),
  ToolCallFixture(
    prompt:
        'Which models do I have installed on this device? Use a tool to '
        'check.',
    expectedTool: 'list_installed_models',
  ),
  ToolCallFixture(
    prompt: 'Search my chat history for the word "icons". Use a tool.',
    expectedTool: 'search_chat_history',
    requiredArguments: ['query'],
  ),
];

/// Tests every tool call against a real model on this device, one prompt at a
/// time, and prints a table that can be copied into a report.
///
/// This is the measurement the model comparison screen cannot make: it sends a
/// prompt and compares speed, while this asks whether the model produced a
/// call the registry would actually run. Everything here is the real path, the
/// real registry for this platform, the real engine and the real validator, so
/// a passing row means the app would have run that tool.
///
/// Run on a device:
///
/// ```bash
/// flutter test integration_test/device_tool_calls_test.dart -d <device-id>
/// ```
///
/// The test skips when no tool-capable model is installed, because a device
/// with nothing installed still proves the registry side.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every fixture tool call runs against a real model', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    final registry = container.read(toolRegistryProvider);

    // The catalog loads asynchronously on its first build, so an immediate
    // read answers with the static list and looks like a device with nothing
    // installed. Holding a listener keeps the controller alive while the
    // wait runs, which is what makes the later reads see its state.
    final subscription = container.listen(
      modelSelectionControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    var installed = container.read(installedAgentModelsProvider);
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (installed.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      installed = container.read(installedAgentModelsProvider);
    }

          // Name a single model to test the others one at a time:
      //   --dart-define=TOOL_TEST_MODEL=qwen3.5
      //
      // Every downloaded model is a candidate, not only the ones that declare
      // tool support: the agent loop sends the tool contract from the registry
      // either way, and the declaration is only filled in by the metadata pass
      // that runs after the catalog loads. Gating on it would skip every model
      // on a freshly installed device, which is the case this harness exists
      // to measure.
      final only = const String.fromEnvironment('TOOL_TEST_MODEL').trim();
      final models = installed
        .where(
          (model) =>
              only.isEmpty ||
              model.name.toLowerCase().contains(only.toLowerCase()) ||
              model.id.toLowerCase().contains(only.toLowerCase()),
        )
        .toList(growable: false);
    if (models.isEmpty) {
      // ignore: avoid_print
      print(
        'skipping: no tool-capable model is installed, so there is nothing '
        'to send the fixtures to. Add a GGUF through Model Selection first.',
      );
      return;
    }

    final model = models.first;
          // ignore: avoid_print
      print('model under test: ${model.name} (${model.id})');
      // ignore: avoid_print
      print(
        'declares tool support: ${model.supportsToolCalling} '
        '(a false here means the app would not offer it in the agent UI)',
      );
    // ignore: avoid_print
    print(
      'tools advertised: '
      '${registry.supportedDefinitions.map((tool) => tool.name).join(', ')}',
    );
    // ignore: avoid_print
    print('');

    final outcomes = <ToolCallOutcome>[];
    for (final fixture in toolCallFixtures) {
      final stopwatch = Stopwatch()..start();
      String? error;
      AgentRun? run;
      try {
        run = await container
            .read(agentLoopServiceProvider)
            .run(
              model: model,
              goal: fixture.prompt,
              registry: registry,
              maxIterations: 3,
              budget: container.read(contextBudgetProvider).budget,
            )
            .timeout(const Duration(minutes: 5));
      } catch (problem) {
        error = problem.toString();
      }
      stopwatch.stop();

      // The first call is the one being scored: a model that calls twice
      // chose correctly on the first try or did not.
      AgentStep? firstCall;
      for (final step in run?.steps ?? const <AgentStep>[]) {
        if (step.kind != AgentStepKind.toolCall) continue;
        firstCall = step;
        break;
      }

      outcomes.add(
        ToolCallOutcome(
          fixture: fixture,
          calledTool: firstCall?.toolName,
          arguments: firstCall?.arguments ?? '',
          status: firstCall?.status,
          iterations: run?.iterations ?? 0,
          toolCalls: run?.toolCallCount ?? 0,
          durationMs: stopwatch.elapsedMilliseconds,
          answer: run?.answer ?? '',
          error: error,
        ),
      );
    }

    // One row per fixture, so the table can be pasted into the report as-is.
    final table = StringBuffer()
      ..writeln('| # | Prompt | Expected | Called | Arguments | Verdict | ms |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      table.writeln(
        '| ${index + 1} '
        '| ${_cell(outcome.fixture.prompt)} '
        '| ${outcome.fixture.expectedTool} '
        '| ${outcome.calledTool ?? '(none)'} '
        '| ${_cell(outcome.arguments.isEmpty ? '(none)' : outcome.arguments)} '
        '| ${outcome.verdict} '
        '| ${outcome.durationMs} |',
      );
    }
    // ignore: avoid_print
    print(table.toString());

    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      // ignore: avoid_print
      print(
        '--- ${index + 1}. ${outcome.fixture.expectedTool} '
        '(${outcome.verdict}) ---',
      );
      // ignore: avoid_print
      print('prompt:   ${outcome.fixture.prompt}');
      // ignore: avoid_print
      print(
        'status:   ${outcome.status ?? '(no tool call)'} '
        'in ${outcome.iterations} iteration(s), '
        '${outcome.toolCalls} call(s)',
      );
      if (outcome.error != null) {
        // ignore: avoid_print
        print('error:    ${outcome.error}');
      }
      // ignore: avoid_print
      print('answer:   ${outcome.answer}');
      // ignore: avoid_print
      print('');
    }

    // A device with a model must reach at least one tool: a run that cannot
    // call anything is a broken wiring, not a weak model, and that is what
    // this assertion separates from the per-fixture verdicts above.
    expect(
      outcomes.where((outcome) => outcome.calledTool != null),
      isNotEmpty,
      reason: 'at least one fixture reached a tool',
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}

/// A table cell: pipes and newlines break the Markdown table.
String _cell(String text) {
  return text.replaceAll('|', '/').replaceAll('\n', ' ').trim();
}
