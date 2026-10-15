import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/features/agents/application/rewind_service.dart';
import 'package:installm/features/agents/application/run_checkpoint_session.dart';
import 'package:installm/features/vault/application/vault_notes_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

/// Exercises run checkpoints and `/rewind` on this machine: the app's own store
/// in the real app-support folder, a real note in a real folder, and the vault
/// service that every other write goes through.
///
/// Unit and widget tests cover the store, the planner and the room flow against
/// temp folders; what they cannot cover is the app's own store path and the
/// real file on this platform. The test prints what it did and puts the store
/// back exactly as it was.
///
/// Run on a desktop or device:
///
/// ```bash
/// flutter test integration_test/device_rewind_smoke_test.dart -d linux
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a run snapshots a note and rewind puts it back', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    final store = await container.read(runCheckpointStoreProvider.future);
    final file = File(store.filePath);
    final original = file.existsSync() ? file.readAsStringSync() : null;
    // ignore: avoid_print
    print('checkpoint store: ${file.path} (existed: ${original != null})');
    addTearDown(() {
      if (original == null) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      file.writeAsStringSync(original);
    });

    final root = Directory.systemTemp.createTempSync('installm_rewind_smoke_');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = VaultPaths(vaultRoot: root.path, projectPath: 'Project');
    final note = File('${root.path}/Project/notes/ok.md');
    note.parent.createSync(recursive: true);
    note.writeAsStringSync('the user wrote this first\n');

    const notes = VaultNotesService();
    final run = RunCheckpointSession(
      store: store,
      contextKey: 'smoke:rewind',
      label: 'Smoke',
      id: 'run-smoke-1',
    );
    // Exactly what a room bot's write does: record before, write, record after.
    run.recordBefore(
      path: paths.projectFile('notes/ok.md')!,
      relativePath: 'notes/ok.md',
      content: await note.readAsString(),
    );
    expect(
      await notes.writeNote(
        paths: paths,
        permissions: VaultPermissions.defaults,
        relativePath: 'notes/ok.md',
        content: 'the agent rewrote this\n',
      ),
      isNull,
    );
    await run.recordAfter(
      path: paths.projectFile('notes/ok.md')!,
      relativePath: 'notes/ok.md',
      content: 'the agent rewrote this\n',
    );

    final stored = store.load().forContext('smoke:rewind');
    expect(stored, hasLength(1));
    expect(stored.single.isRestorable, isTrue);
    // ignore: avoid_print
    print(
      'run ${stored.single.id}: ${stored.single.entries.length} file(s), '
      'before kept: ${stored.single.entries.single.beforeContent?.trim()}',
    );
    expect(await note.readAsString(), 'the agent rewrote this\n');

    final outcome = await const RewindService().rewind(
      run: stored.single,
      paths: paths,
    );
    // ignore: avoid_print
    print('rewind restored=${outcome.restored}: ${outcome.message}');
    expect(outcome.restored, isTrue, reason: outcome.message);
    expect(await note.readAsString(), 'the user wrote this first\n');

    // An edit after the run is kept, whatever the user asks for.
    expect(
      await notes.writeNote(
        paths: paths,
        permissions: VaultPermissions.defaults,
        relativePath: 'notes/ok.md',
        content: 'the agent rewrote this\n',
      ),
      isNull,
    );
    note.writeAsStringSync('the user edited it afterwards\n');
    final refused = await const RewindService().rewind(
      run: stored.single,
      paths: paths,
    );
    // ignore: avoid_print
    print('second rewind restored=${refused.restored}: ${refused.message}');
    expect(refused.restored, isFalse);
    expect(refused.message, contains('changed after this run wrote it'));
    expect(await note.readAsString(), 'the user edited it afterwards\n');
  });
}
