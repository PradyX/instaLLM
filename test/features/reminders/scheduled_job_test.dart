import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/reminders/data/scheduled_task_store.dart';
import 'package:installm/features/reminders/domain/job_policy.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';
import 'package:path/path.dart' as p;

ScheduledTask _job({
  DateTime? at,
  String prompt = 'Summarise my unread notes',
  String? modelName,
}) {
  final now = DateTime(2026, 11, 22, 7);
  return ScheduledTask.create(
    title: 'Morning brief',
    prompt: prompt,
    modelName: modelName,
    nextRunAt: at ?? now,
    now: now,
  );
}

void main() {
  final due = DateTime(2026, 11, 22, 7);

  group('a due job', () {
    test('runs when the model is ready and nothing else is generating', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due,
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isTrue);
      expect(gate.reason, isNull);
    });

    test('is skipped with a reason once the app was not there to run it', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due.add(const Duration(hours: 3)),
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('app was not running'));
      expect(gate.reason, contains('07:00'));
    });

    test('is not treated as late when the user ran it on purpose', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due.add(const Duration(hours: 2)),
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
        manual: true,
      );

      expect(gate.shouldRun, isTrue);
    });

    test('a manual run still refuses when no model is ready', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due.add(const Duration(hours: 2)),
        modelReady: false,
        generating: false,
        selectedModelName: null,
        manual: true,
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('No model'));
    });

    test('still runs inside the grace window', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due.add(const Duration(minutes: 2)),
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isTrue);
    });

    test('is skipped when no model is ready', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due,
        modelReady: false,
        generating: false,
        selectedModelName: null,
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('No model'));
    });

    test('is skipped while another reply is being generated', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(),
        now: due,
        modelReady: true,
        generating: true,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('Another reply'));
    });

    test('is skipped when the model it was scheduled for is not the selected '
        'one, instead of quietly using another', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(modelName: 'Qwen'),
        now: due,
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('Qwen'));
      expect(gate.reason, contains('SmolLM2'));
    });

    test('a task without a prompt is not a job at all', () {
      final gate = ScheduledJobPolicy.gate(
        task: _job(prompt: ''),
        now: due,
        modelReady: true,
        generating: false,
        selectedModelName: 'SmolLM2',
      );

      expect(gate.shouldRun, isFalse);
      expect(gate.reason, contains('no prompt'));
    });
  });

  group('run records', () {
    test('keep their state, times, summary and reason through JSON', () {
      final run =
          TaskRun(
            id: 'run-1',
            state: TaskRunState.skipped,
            startedAt: due,
            finishedAt: due.add(const Duration(seconds: 2)),
            reason: 'No model is ready on this device.',
            modelName: 'SmolLM2',
          ).finish(
            state: TaskRunState.completed,
            finishedAt: due.add(const Duration(seconds: 5)),
            summary: 'Three notes, one action.',
            modelName: 'SmolLM2',
          );

      final restored = TaskRun.fromJson(run.toJson())!;
      expect(restored.state, TaskRunState.completed);
      expect(restored.summary, 'Three notes, one action.');
      // A finished run carries the finish reason, not the one it started with.
      expect(restored.reason, isNull);
      expect(restored.finishedAt, due.add(const Duration(seconds: 5)));
      expect(restored.duration, const Duration(seconds: 5));
      expect(restored.headline, 'Three notes, one action.');
      expect(restored.modelName, 'SmolLM2');
    });

    test('a running job does not claim a finish time', () {
      final run = TaskRun(
        id: 'run-2',
        state: TaskRunState.running,
        startedAt: due,
      );

      expect(run.finishedAt, isNull);
      expect(run.duration, isNull);
      expect(run.headline, 'Running');
    });

    test('are kept newest first and bounded', () {
      var task = _job();
      for (var i = 0; i < ScheduledTaskLimits.maxRunsPerTask + 5; i++) {
        task = task.withRun(
          TaskRun(
            id: 'run-$i',
            state: TaskRunState.completed,
            startedAt: due.add(Duration(minutes: i)),
            finishedAt: due.add(Duration(minutes: i, seconds: 1)),
            summary: 'answer $i',
          ),
        );
      }

      expect(task.runs, hasLength(ScheduledTaskLimits.maxRunsPerTask));
      expect(
        task.runs.first.id,
        'run-${ScheduledTaskLimits.maxRunsPerTask + 4}',
      );
      expect(task.latestRun!.summary, contains('answer'));
    });

    test('a prompt survives storage and makes the task a job', () {
      final task = _job(prompt: 'Write the standup note');
      final restored = ScheduledTask.fromJson(
        jsonDecode(jsonEncode(task.toJson())) as Map<String, dynamic>,
      )!;

      expect(restored.isJob, isTrue);
      expect(restored.prompt, 'Write the standup note');
    });
  });

  group('the task store', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('installm-jobs');
    });

    tearDown(() async {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    File storeFile() => File(p.join(directory.path, 'scheduled_tasks.json'));

    test('reads a version 1 file as plain reminders and migrates on save', () {
      final file = storeFile()..createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'tasks': [
            {
              'id': 'task-1',
              'title': 'Stretch',
              'body': 'Ten minutes',
              'nextRunAt': '2026-11-23T07:00:00.000',
              'recurrence': 'daily',
              'enabled': true,
              'createdAt': '2026-11-20T07:00:00.000',
              'updatedAt': '2026-11-20T07:00:00.000',
            },
          ],
        }),
      );

      final store = ScheduledTaskStore(file);
      final tasks = store.load();
      expect(tasks, hasLength(1));
      expect(tasks.single.isJob, isFalse);
      expect(tasks.single.runs, isEmpty);
      expect(store.isReadOnly, isFalse);

      expect(store.save(tasks), isTrue);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(saved['version'], ScheduledTaskStore.currentVersion);
      // The original file is kept, not overwritten in place.
      final backups = directory
          .listSync()
          .whereType<File>()
          .where((entry) => entry.path.contains('.preserved-'))
          .toList();
      expect(backups, hasLength(1));
      expect(
        jsonDecode(backups.single.readAsStringSync()) as Map<String, dynamic>,
        containsPair('version', 1),
      );
    });

    test('round-trips a job with its runs', () {
      final file = storeFile();
      final store = ScheduledTaskStore(file);
      final task = _job().withRun(
        TaskRun(
          id: 'run-9',
          state: TaskRunState.completed,
          startedAt: due,
          finishedAt: due.add(const Duration(seconds: 3)),
          summary: 'One note, nothing else.',
        ),
      );

      expect(store.save([task]), isTrue);
      final reloaded = ScheduledTaskStore(file).load().single;
      expect(reloaded.isJob, isTrue);
      expect(reloaded.latestRun!.state, TaskRunState.completed);
      expect(reloaded.latestRun!.summary, 'One note, nothing else.');
    });

    test('a file from a newer build stays read-only', () {
      final file = storeFile()..createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({'version': ScheduledTaskStore.currentVersion + 1}),
      );

      final store = ScheduledTaskStore(file);
      expect(store.load(), isEmpty);
      expect(store.isReadOnly, isTrue);
      expect(store.save(const []), isFalse);
    });
  });
}
