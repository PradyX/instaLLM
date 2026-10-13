import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/kanban/data/task_repository.dart';
import 'package:installm/features/kanban/domain/task.dart';
import 'package:installm/features/kanban/domain/task_note_codec.dart';
import 'package:installm/features/obsidian/application/vault_notes_service.dart';
import 'package:installm/features/obsidian/domain/vault_paths.dart';
import 'package:installm/features/obsidian/domain/vault_registration.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('task_links');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  ProjectTask task() =>
      ProjectTask.create(
        id: 'PL-001',
        workspaceId: 'ws',
        title: 'Room task',
        description: 'Details\n\n## Activity\nKeep this description heading.',
        createdBy: 'user',
        now: DateTime.utc(2026, 10, 12, 11, 12, 13),
      ).copyWith(
        relatedRoomIds: ['room-1'],
        relatedMessages: ['message-1'],
        relatedDocuments: ['Plans/a.md'],
        dependencies: ['PL-000'],
        comments: [
          TaskComment(
            author: 'user',
            text: 'First line\nSecond line',
            createdAt: DateTime.utc(2026, 10, 13),
          ),
        ],
      );

  test(
    'v1 local tasks migrate on save and preserve valid partial entries',
    () async {
      final file = File('${directory.path}/ws/tasks.json')
        ..parent.createSync(recursive: true);
      final legacy = task().toJson()..remove('relatedRoomIds');
      legacy['status'] = 7;
      legacy['priority'] = false;
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'tasks': [
            null,
            {'id': 3},
            legacy,
          ],
        }),
      );
      final repository = LocalTaskRepository(directory);
      final loaded = await repository.load('ws');
      expect(loaded, hasLength(1));
      expect(loaded.single.relatedRoomIds, isEmpty);
      expect(loaded.single.relatedMessages, ['message-1']);
      expect(loaded.single.status, TaskStatus.todo);
      await repository.save('ws', [
        loaded.single.copyWith(relatedRoomIds: ['room-1']),
      ]);
      expect(jsonDecode(file.readAsStringSync())['version'], 2);
      final restarted = (await LocalTaskRepository(
        directory,
      ).load('ws')).single;
      expect(restarted.relatedRoomIds, ['room-1']);
      expect(restarted.comments.single.text, 'First line\nSecond line');
    },
  );

  test(
    'future local schema refuses both load and direct save without changing data',
    () async {
      final file = File('${directory.path}/ws/tasks.json')
        ..parent.createSync(recursive: true);
      const original = '{"version": 99, "tasks": []}';
      file.writeAsStringSync(original);
      final repository = LocalTaskRepository(directory);
      await expectLater(
        repository.load('ws'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        repository.save('ws', [task()]),
        throwsA(isA<FileSystemException>()),
      );
      expect(file.readAsStringSync(), original);
    },
  );

  test(
    'corrupt local data is copied aside before new tasks are saved',
    () async {
      final file = File('${directory.path}/ws/tasks.json')
        ..parent.createSync(recursive: true);
      file.writeAsStringSync('{broken');
      final repository = LocalTaskRepository(directory);
      expect(await repository.load('ws'), isEmpty);
      await repository.save('ws', [task()]);
      final backup = file.parent.listSync().whereType<File>().singleWhere(
        (file) => file.path.contains('.corrupt-'),
      );
      expect(backup.readAsStringSync(), '{broken');
      expect((await repository.load('ws')).single.relatedRoomIds, ['room-1']);
    },
  );

  test(
    'vault task links, messages, dates and multiline activity survive reload and a status change',
    () async {
      final paths = VaultPaths(
        vaultRoot: directory.path,
        projectPath: 'Projects/Test',
      );
      await const VaultNotesService().ensureProjectStructure(
        paths,
        projectName: 'Test',
      );
      final repository = VaultTaskRepository(
        paths: paths,
        permissions: VaultPermissions.defaults,
      );
      final original = task();
      await repository.save('ws', [original]);
      final loaded = (await repository.load('ws')).single;
      expect(loaded.relatedRoomIds, original.relatedRoomIds);
      expect(loaded.relatedMessages, original.relatedMessages);
      expect(loaded.createdAt, original.createdAt);
      expect(loaded.updatedAt, original.updatedAt);
      expect(loaded.createdBy, 'user');
      expect(loaded.description, original.description);
      expect(
        loaded.comments.single.toJson(),
        original.comments.single.toJson(),
      );
      await repository.save('ws', [loaded.copyWith(status: TaskStatus.done)]);
      final reopened = (await repository.load('ws')).single;
      expect(reopened.status, TaskStatus.done);
      expect(reopened.completedAt, isNotNull);
      expect(reopened.relatedRoomIds, ['room-1']);
      expect(reopened.comments.single.text, original.comments.single.text);
    },
  );

  test(
    'legacy Markdown reads dates/activity and partial links; future notes stay untouched',
    () async {
      const legacy =
          '---\nid: PL-001\ncreated: 2026-10-12\nrooms:\n  - "room-1"\nmessages:\n  - "m1"\n---\n# Old task\n\nDescription\n\n## Activity\n\n- **user** (2026-10-12): Keep this activity\n';
      final decoded = TaskNoteCodec.decode(legacy, workspaceId: 'ws')!;
      expect(decoded.createdAt, DateTime(2026, 10, 12));
      expect(decoded.comments.single.text, 'Keep this activity');
      expect(decoded.relatedMessages, ['m1']);
      expect(decoded.relatedRoomIds, ['room-1']);
      final paths = VaultPaths(vaultRoot: directory.path, projectPath: 'Test');
      await const VaultNotesService().ensureProjectStructure(
        paths,
        projectName: 'Test',
      );
      final note = File(
        paths.projectFile('Tasks/${TaskNoteCodec.fileName(task())}')!,
      );
      final future = TaskNoteCodec.encode(
        task(),
      ).replaceFirst('schema_version: 2', 'schema_version: 99');
      note.writeAsStringSync(future);
      final repository = VaultTaskRepository(
        paths: paths,
        permissions: VaultPermissions.defaults,
      );
      await expectLater(repository.load('ws'), throwsFormatException);
      await expectLater(repository.save('ws', [task()]), throwsFormatException);
      expect(note.readAsStringSync(), future);
    },
  );

  test(
    'denied vault writes report failure instead of claiming a saved task',
    () async {
      final paths = VaultPaths(vaultRoot: directory.path, projectPath: 'Test');
      await const VaultNotesService().ensureProjectStructure(
        paths,
        projectName: 'Test',
      );
      final repository = VaultTaskRepository(
        paths: paths,
        permissions: const VaultPermissions(canWrite: false),
      );
      await expectLater(
        repository.save('ws', [task()]),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
