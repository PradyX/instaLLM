import 'dart:convert';

import 'package:pocket_llm/features/kanban/domain/task.dart';

/// Converts tasks to and from Obsidian-friendly Markdown notes (§9.2).
///
/// ```markdown
/// ---
/// id: PL-001
/// status: in-progress
/// priority: high
/// assignee: coder
/// depends_on:
///   - PL-000
/// created: 2026-09-30
/// ---
///
/// # Title
///
/// Description...
/// ```
/// Human readable, Git friendly, searchable and agent editable; the board is
/// constructed from these notes. Unknown keys are ignored and missing keys
/// fall back, so a hand-written note still boards.
abstract final class TaskNoteCodec {
  static const currentVersion = 2;

  static bool isSupported(String text) {
    if (!text.startsWith('---')) return true;
    final end = text.indexOf('\n---', 3);
    if (end < 0) return true;
    final match = RegExp(
      r'^schema_version:\s*(\d+)\s*$',
      multiLine: true,
    ).firstMatch(text.substring(0, end));
    return match == null || int.parse(match.group(1)!) <= currentVersion;
  }

  /// File name for [task]: `PL-001-short-slug.md`.
  static String fileName(ProjectTask task) {
    final slug = task.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = slug.length > 40 ? slug.substring(0, 40) : slug;
    return '${task.id}-${trimmed.isEmpty ? 'task' : trimmed}.md';
  }

  static String encode(ProjectTask task) {
    final buffer = StringBuffer('---\n');
    buffer.writeln('schema_version: $currentVersion');
    buffer.writeln('id: ${task.id}');
    buffer.writeln('status: ${task.status.key}');
    buffer.writeln('priority: ${task.priority.name}');
    if (task.assignedBotId != null) {
      buffer.writeln('assignee: ${task.assignedBotId}');
    }
    if (task.parentTaskId != null) {
      buffer.writeln('parent: ${task.parentTaskId}');
    }
    if (task.dependencies.isNotEmpty) {
      buffer.writeln('depends_on:');
      for (final dependency in task.dependencies) {
        buffer.writeln('  - $dependency');
      }
    }
    if (task.relatedDocuments.isNotEmpty) {
      buffer.writeln('documents:');
      for (final document in task.relatedDocuments) {
        buffer.writeln('  - $document');
      }
    }
    for (final entry in {
      'rooms': task.relatedRoomIds,
      'messages': task.relatedMessages,
    }.entries) {
      if (entry.value.isEmpty) continue;
      buffer.writeln('${entry.key}:');
      for (final id in entry.value) {
        buffer.writeln('  - ${jsonEncode(id)}');
      }
    }
    if (task.createdBy != null) {
      buffer.writeln('created_by: ${jsonEncode(task.createdBy)}');
    }
    if (task.comments.isNotEmpty) {
      buffer.writeln(
        'activity_json: ${jsonEncode(task.comments.map((comment) => comment.toJson()).toList())}',
      );
    }
    buffer.writeln('created: ${task.createdAt.toIso8601String()}');
    buffer.writeln('updated: ${task.updatedAt.toIso8601String()}');
    if (task.completedAt != null) {
      buffer.writeln('completed: ${task.completedAt!.toIso8601String()}');
    }
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('# ${task.title}');
    if (task.description.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(task.description);
    }
    if (task.comments.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## Activity');
      buffer.writeln();
      for (final comment in task.comments) {
        buffer.writeln(
          '- **${comment.author}** '
          '(${comment.createdAt.toIso8601String().substring(0, 10)}): '
          '${comment.text}',
        );
      }
    }
    return buffer.toString();
  }

  /// Parses a note written by [encode] (or by hand) into a task scoped to
  /// [workspaceId]. Returns null when the note carries no usable id.
  static ProjectTask? decode(String text, {required String workspaceId}) {
    if (!isSupported(text)) return null;
    var body = text;
    final frontmatter = <String, Object>{};
    if (text.startsWith('---')) {
      final end = text.indexOf('\n---', 3);
      if (end >= 0) {
        final firstNewline = text.indexOf('\n');
        frontmatter.addAll(
          _parseFrontmatter(
            firstNewline >= 0 && firstNewline < end
                ? text.substring(firstNewline + 1, end)
                : '',
          ),
        );
        body = end + 4 < text.length ? text.substring(end + 4) : '';
      }
    }

    final rawId = frontmatter['id'];
    if (rawId is! String || rawId.trim().isEmpty) return null;
    final id = rawId.trim();

    var title = '';
    final description = StringBuffer();
    final activityLines = <String>[];
    final activityStart = body.lastIndexOf('\n## Activity\n');
    final hasActivity =
        frontmatter['schema_version'] != '$currentVersion' ||
        frontmatter.containsKey('activity_json');
    if (hasActivity && activityStart >= 0) {
      activityLines.addAll(
        body.substring(activityStart + '\n## Activity\n'.length).split('\n'),
      );
      body = body.substring(0, activityStart);
    }
    for (final line in body.split('\n')) {
      if (line.startsWith('# ') && title.isEmpty) {
        title = line.substring(2).trim();
        continue;
      }
      description.writeln(line);
    }

    List<String> readList(Object? value) {
      if (value is List<String>) return value;
      if (value is! List) return const [];
      return value.whereType<String>().toList(growable: false);
    }

    String? readOpt(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    final comments = <TaskComment>[];
    final rawActivity = readOpt(frontmatter['activity_json']);
    if (rawActivity != null) {
      try {
        final decoded = jsonDecode(rawActivity);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map<String, dynamic>>()) {
            final comment = TaskComment.fromJson(entry);
            if (comment != null) comments.add(comment);
          }
        }
      } catch (_) {
        /* Keep readable legacy activity below. */
      }
    }
    if (comments.isEmpty) {
      final pattern = RegExp(r'^- \*\*(.*?)\*\* \((.*?)\): (.*)$');
      for (final line in activityLines) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          comments.add(
            TaskComment(
              author: match.group(1)!,
              text: match.group(3)!,
              createdAt:
                  DateTime.tryParse(match.group(2)!) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        } else if (comments.isNotEmpty && line.trim().isNotEmpty) {
          final previous = comments.removeLast();
          comments.add(
            TaskComment(
              author: previous.author,
              text: '${previous.text}\n$line',
              createdAt: previous.createdAt,
            ),
          );
        }
      }
    }
    DateTime? date(String key) =>
        DateTime.tryParse(readOpt(frontmatter[key]) ?? '');
    final created = date('created') ?? DateTime.fromMillisecondsSinceEpoch(0);

    return ProjectTask(
      id: id,
      workspaceId: workspaceId,
      title: title.isEmpty ? id : title,
      description: description.toString().trim(),
      status: TaskStatus.fromKey(readOpt(frontmatter['status']) ?? 'todo'),
      priority: TaskPriority.fromName(readOpt(frontmatter['priority'])),
      assignedBotId: readOpt(frontmatter['assignee']),
      parentTaskId: readOpt(frontmatter['parent']),
      dependencies: readList(frontmatter['depends_on']),
      relatedDocuments: readList(frontmatter['documents']),
      relatedMessages: readList(frontmatter['messages']),
      relatedRoomIds: readList(frontmatter['rooms']),
      createdBy: readOpt(frontmatter['created_by']),
      comments: comments,
      createdAt: created,
      updatedAt: date('updated') ?? created,
      completedAt: date('completed'),
    );
  }

  static Map<String, Object> _parseFrontmatter(String block) {
    final result = <String, Object>{};
    String? listKey;
    final items = <String>[];
    String scalar(String value) {
      if (value.startsWith('"')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String) return decoded;
        } catch (_) {
          /* Legacy raw value. */
        }
      }
      return value;
    }

    void flush() {
      if (listKey != null) {
        result[listKey!] = List<String>.unmodifiable(items);
        items.clear();
        listKey = null;
      }
    }

    for (final rawLine in block.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('- ')) {
        if (listKey != null) items.add(scalar(trimmed.substring(2).trim()));
        continue;
      }
      flush();
      final colon = trimmed.indexOf(':');
      if (colon < 0) continue;
      final key = trimmed.substring(0, colon).trim();
      final value = trimmed.substring(colon + 1).trim();
      if (key.isEmpty) continue;
      if (value.isEmpty) {
        listKey = key;
        continue;
      }
      result[key] = scalar(value);
    }
    flush();
    return result;
  }
}
