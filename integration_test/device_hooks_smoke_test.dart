import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/features/agents/application/hooks_controller.dart';
import 'package:installm/features/agents/data/hook_store.dart';
import 'package:installm/features/agents/presentation/hooks_page.dart';
import 'package:installm/features/tools/application/tool_approval_controller.dart';
import 'package:installm/features/tools/application/tools_providers.dart';
import 'package:installm/features/tools/domain/tool_call.dart';
import 'package:installm/features/tools/domain/tool_execution_result.dart';
import 'package:installm/features/vault/application/bot_journal_service.dart';
import 'package:installm/features/vault/data/journal_checkpoint_store.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// Exercises the real hook wiring on this machine: the app's own hook file in
/// the real app-support folder, the provider graph the registry is built from,
/// and a real refusal of a real note write.
///
/// Unit and widget tests cover the rule engine, the store and the page against
/// temp folders; what they cannot cover is whether the app's own registry —
/// built for this platform, with the user's real hooks file — refuses a call
/// before a file is written. The test prints what it found and puts the user's
/// hooks file back exactly as it was.
///
/// Run on a desktop or device:
///
/// ```bash
/// flutter test integration_test/device_hooks_smoke_test.dart -d linux
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the real registry refuses a protected write, then allows it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    final store = await container.read(hookStoreProvider.future);
    final path = store.filePath;
    final file = File(path);
    final original = file.existsSync() ? file.readAsStringSync() : null;
    // ignore: avoid_print
    print('hooks file under test: $path (existed: ${original != null})');
    addTearDown(() async {
      if (original == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(original);
    });

    final hooks = container.read(hooksProvider.notifier);
    await hooks.whenReady;
    final before = container.read(hooksProvider).hooks.length;
    final rule = await hooks.addHook(
      name: 'Smoke: protect secrets',
      resourcePattern: 'secrets/**',
    );
    expect(rule, isNotNull, reason: 'the app stored the rule it was given');
    // ignore: avoid_print
    print('rules before: $before · after: ${hooks.state.hooks.length}');

    final root = Directory.systemTemp.createTempSync('installm_hooks_smoke_');
    addTearDown(() => root.deleteSync(recursive: true));
    final session = (await BotJournalSession.open(
      paths: VaultPaths(vaultRoot: root.path, projectPath: 'Project'),
      permissions: VaultPermissions.defaults,
      botId: 'smoke',
      checkpoints: JournalCheckpointStore(File('${root.path}/points.json')),
    ))!;

    // The app's own registry, extended with the vault tools a room or home
    // chat adds, so the hooks the user's file holds are the ones in force.
    final registry = container
        .read(toolRegistryProvider)
        .extendedWith(session.tools());
    final protected = File('${root.path}/Project/secrets/keys.md');

    final refused = await registry.execute(
      const ToolCall(
        toolName: 'vault_write_note',
        arguments: {
          'relativePath': 'secrets/keys.md',
          'summary': 'Should never be written.',
        },
      ),
    );
    // ignore: avoid_print
    print('protected write: ${refused.status.name} · ${refused.output}');
    expect(refused.status, ToolExecutionStatus.denied);
    expect(refused.output, contains('Smoke: protect secrets'));
    expect(
      protected.existsSync(),
      isFalse,
      reason: 'nothing reached the disk for a refused call',
    );

    expect(await hooks.removeHook(rule!.id), isTrue);
    // With the rule gone the call reaches the app's own permission prompt, so
    // the answer to that question is what decides it — exactly as in the chat.
    final pending = registry.execute(
      const ToolCall(
        toolName: 'vault_write_note',
        arguments: {
          'relativePath': 'notes/ok.md',
          'summary': 'Written after the rule was removed.',
        },
      ),
    );
    for (var attempt = 0; attempt < 100; attempt++) {
      if (container.read(toolApprovalControllerProvider) != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final question = container.read(toolApprovalControllerProvider);
    expect(question, isNotNull, reason: 'the app asked before the call ran');
    // ignore: avoid_print
    print('permission question after removal: ${question!.summary}');
    container.read(toolApprovalControllerProvider.notifier).approve();
    final allowed = await pending;
    // ignore: avoid_print
    print('write after removal: ${allowed.status.name} · ${allowed.output}');
    expect(allowed.isSuccess, isTrue, reason: allowed.output);
    expect(File('${root.path}/Project/notes/ok.md').existsSync(), isTrue);
    expect(container.read(hooksProvider).hooks.length, before);
  });

  testWidgets('the hooks page renders and stores a rule on this machine', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = await container.read(hookStoreProvider.future);
    final file = File(store.filePath);
    final original = file.existsSync() ? file.readAsStringSync() : null;
    addTearDown(() async {
      if (original == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(original);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HooksPage()),
      ),
    );
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (container.read(hooksProvider).isReady) break;
    }
    await tester.pumpAndSettle();

    expect(find.byType(HooksPage), findsOneWidget);
    expect(find.text('Git internals'), findsOneWidget);
    expect(find.text('Add rule'), findsOneWidget);
    // ignore: avoid_print
    print('hooks page rendered with the built-in floor listed');

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('hook-name')),
      'Smoke page rule',
    );
    await tester.enterText(
      find.byKey(const ValueKey('hook-path')),
      'drafts/**',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (container.read(hooksProvider).hooks.isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    final stored = HookStore(file).load().hooks;
    // ignore: avoid_print
    print('rules in ${file.path}: ${stored.map((hook) => hook.name).toList()}');
    expect(stored.any((hook) => hook.name == 'Smoke page rule'), isTrue);
    expect(find.text('Smoke page rule'), findsOneWidget);
  });
}
