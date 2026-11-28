import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/android_tool_executor_service.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/mcp/domain/mcp_capabilities.dart';
import 'package:installm/features/mcp/domain/mcp_server.dart';
import 'package:installm/features/mcp/domain/mcp_tool_filter.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/tools/application/built_in_tools.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';
import 'package:integration_test/integration_test.dart';

/// Records the approval question instead of showing one, and never approves.
///
/// A sensitive tool must stop here: approving would open the real alarm, event
/// or SMS app on the device running this test.
class _RefusingGate implements ToolPermissionGate {
  final List<String> asked = [];

  @override
  Future<bool> requestApproval(ToolApprovalRequest request) async {
    asked.add(request.summary);
    return false;
  }
}

/// One line of the report.
class _Row {
  _Row(this.tool, this.status, this.detail);

  final String tool;
  final String status;
  final String detail;

  String get line => '| $tool | $status | $detail |';
}

String _oneLine(String text) {
  final flat = text.replaceAll('\n', ' ').trim();
  return flat.length <= 110 ? flat : '${flat.substring(0, 110)}…';
}

/// Waits for a controller that loads itself in the background.
///
/// The app opens these screens before a turn runs, so a tool sees loaded state;
/// this test reads the same providers and waits the same way.
Future<void> _waitUntil(bool Function() done, {required String what}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('$what did not load in 30s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Runs every tool the app offers through the real registry on this device and
/// prints one table.
///
/// The read-only tools run for real: they read the app's own chat history,
/// knowledge collection and installed models. The three Android actions are
/// stopped at the approval gate, because approving one would open the alarm,
/// calendar or SMS app on the device. The MCP cap is checked on the same
/// selection the turn uses.
///
/// Run `scripts/test_android.sh integration_test/device_tool_report_test.dart`
/// with the device serial.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every tool runs or is refused where it should be', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // These providers are auto-dispose, so a bare read would tear them down
    // halfway through loading; the screens keep listeners, and so does this.
    final keepAlive = [
      container.listen(conversationControllerProvider, (_, _) {}),
      container.listen(modelSelectionControllerProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final subscription in keepAlive) {
        subscription.close();
      }
    });

    final rows = <_Row>[];
    final safeStatuses = <String, ToolExecutionStatus>{};
    late ToolExecutionResult invalid;
    final sensitiveStatuses = <String, ToolExecutionStatus>{};
    final gate = _RefusingGate();
    var ranSensitive = false;
    late List<McpToolChoice> chosen;
    late String chatHistoryOutput;

    // Real file I/O never completes under the test clock, so the whole report
    // runs with real async.
    await tester.runAsync(() async {
      await _waitUntil(
        () => container.read(conversationControllerProvider).isInitialized,
        what: 'the conversation list',
      );
      await _waitUntil(
        () => !container.read(modelSelectionControllerProvider).isLoadingModels,
        what: 'the model library',
      );

      // The installed build starts with an empty library, so seed one
      // conversation for the chat-history search to find. The test build's
      // storage goes away when the run uninstalls it.
      final conversations = container.read(
        conversationControllerProvider.notifier,
      );
      final seeded = await conversations.createConversation(
        title: 'Tool report seed',
      );
      await conversations.saveConversationMessages(seeded.id, [
        Message(
          id: 'tool-report-seed',
          conversationId: seeded.id,
          role: MessageRole.user,
          content: 'Try the calculator on 2 plus 2.',
          createdAt: DateTime.now(),
        ),
      ]);

      final registry = container.read(toolRegistryProvider);

      // 1. The read-only tools, through the app's own registry.
      final safeCalls = <ToolCall>[
        const ToolCall(
          toolName: 'calculator',
          arguments: {'expression': '(137 * 29) + 18'},
        ),
        const ToolCall(
          toolName: 'current_datetime',
          arguments: {'timezone': 'local'},
        ),
        const ToolCall(
          toolName: 'search_chat_history',
          arguments: {'query': 'calculator', 'limit': 3},
        ),
        const ToolCall(
          toolName: 'search_local_documents',
          arguments: {'query': 'calculator', 'limit': 3},
        ),
        const ToolCall(toolName: 'list_installed_models', arguments: {}),
      ];
      for (final call in safeCalls) {
        final result = await registry.execute(call);
        safeStatuses[call.toolName] = result.status;
        if (call.toolName == 'search_chat_history') {
          chatHistoryOutput = result.output;
        }
        rows.add(
          _Row(call.toolName, result.status.name, _oneLine(result.output)),
        );
      }

      // A wrong call must be rejected by the validator, not run.
      invalid = await registry.execute(
        const ToolCall(toolName: 'calculator', arguments: {'sum': '1+1'}),
      );
      rows.add(
        _Row(
          'calculator (bad arguments)',
          invalid.status.name,
          _oneLine(invalid.output),
        ),
      );

      // 2. The Android actions: validated, then stopped at the gate.
      final androidRegistry = ToolRegistry(
        tools: builtInToolEntries(
          androidActions: (toolName, arguments) async {
            ranSensitive = true;
            return AndroidToolExecutionResult.success(
              message: 'should never run',
              toolName: toolName,
            );
          },
        ),
        platform: ToolPlatform.android,
        permissionGate: gate,
      );
      final sensitiveCalls = <ToolCall>[
        const ToolCall(
          toolName: 'set_alarm',
          arguments: {'hour': 7, 'minute': 30},
        ),
        const ToolCall(
          toolName: 'create_event',
          arguments: {
            'title': 'Tool report',
            'start_time': '2026-11-29T09:00:00',
          },
        ),
        const ToolCall(
          toolName: 'send_sms',
          arguments: {'phone': '+10000000000', 'message': 'hello'},
        ),
      ];
      for (final call in sensitiveCalls) {
        final result = await androidRegistry.execute(call);
        sensitiveStatuses[call.toolName] = result.status;
        rows.add(
          _Row(call.toolName, result.status.name, _oneLine(result.output)),
        );
      }

      // 3. The MCP cap: more tools than fit are cut to the per-turn maximum.
      final now = DateTime.now();
      final server = McpServer(
        id: 'report-server',
        name: 'Report',
        createdAt: now,
        updatedAt: now,
      );
      final capabilities = McpCapabilities(
        serverId: server.id,
        tools: [
          for (var index = 0; index < 12; index++)
            McpToolInfo(
              name: 'tool_$index',
              description: 'Tool number $index for the report',
            ),
        ],
      );
      chosen = McpToolFilter.select(
        servers: [server],
        capabilities: {server.id: capabilities},
        taskText: 'use a tool from the report server',
      );
      rows.add(
        _Row(
          'MCP tools offered',
          chosen.length == McpToolFilter.maxToolsPerTask ? 'capped' : 'wrong',
          '${chosen.length} of 12 chosen, cap ${McpToolFilter.maxToolsPerTask}',
        ),
      );
    });

    final table = StringBuffer()
      ..writeln('| tool | status | detail |')
      ..writeln('|---|---|---|');
    for (final row in rows) {
      table.writeln(row.line);
    }
    // ignore: avoid_print
    print(table.toString());

    // The report is also the assertion: each tool must land where it should.
    for (final name in [
      'calculator',
      'current_datetime',
      'search_chat_history',
      'search_local_documents',
      'list_installed_models',
    ]) {
      expect(
        safeStatuses[name],
        ToolExecutionStatus.success,
        reason: '$name runs on this device',
      );
    }
    expect(
      invalid.status,
      ToolExecutionStatus.invalidArguments,
      reason: 'a misspelled argument is refused',
    );
    for (final name in ['set_alarm', 'create_event', 'send_sms']) {
      expect(
        sensitiveStatuses[name],
        ToolExecutionStatus.denied,
        reason: '$name waits for the user',
      );
    }
    expect(
      chatHistoryOutput,
      contains('matching message'),
      reason: 'the chat-history search reads the seeded conversation',
    );
    expect(gate.asked, hasLength(3), reason: 'each sensitive call asks once');
    expect(ranSensitive, isFalse, reason: 'nothing ran without approval');
    expect(chosen, hasLength(McpToolFilter.maxToolsPerTask));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
