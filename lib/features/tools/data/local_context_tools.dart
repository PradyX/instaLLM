import 'dart:io';

import 'package:installm/features/connections/domain/connector_config.dart';
import 'package:installm/features/documents/data/web_fetch_service.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/domain/tool_definition.dart';

/// Tool: check-my-day from user-picked ICS files.
///
/// Read-only and offline: local files the user picked, never a server.
/// Sensitive so the registry asks first — the calendar is personal even when
/// it never leaves the device.
ToolEntry buildCalendarTool({required List<String> Function() icsPaths}) {
  return ToolEntry(
    definition: const ToolDefinition(
      name: 'check_my_day',
      description:
          'Reads the calendars the user added (local ICS files) and lists '
          'what is scheduled. Read-only and offline; nothing is fetched.',
      risk: ToolRiskLevel.sensitive,
      timeout: Duration(seconds: 10),
      parameters: [
        ToolParameter(
          name: 'date',
          type: ToolParameterType.string,
          description: 'Day to check as YYYY-MM-DD; empty means today.',
          required: false,
          maxLength: 10,
        ),
      ],
    ),
    handler: (arguments) async {
      final paths = icsPaths();
      if (paths.isEmpty) {
        return 'No calendars are connected. The user can add an ICS file in Settings › Connections.';
      }
      final rawDate = (arguments['date'] as String? ?? '').trim();
      final day = DateTime.tryParse(rawDate) ?? DateTime.now();
      final events = <IcsEvent>[];
      for (final path in paths.take(5)) {
        try {
          final content = await File(path).readAsString();
          events.addAll(IcsParser.parse(content));
        } catch (_) {
          // One unreadable file must not hide the others.
        }
      }
      final sameDay = events
          .where(
            (event) =>
                event.start != null &&
                event.start!.year == day.year &&
                event.start!.month == day.month &&
                event.start!.day == day.day,
          )
          .take(10)
          .toList();
      if (sameDay.isEmpty) {
        return 'Nothing is scheduled for ${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} in the connected calendars.';
      }
      final buffer = StringBuffer()..writeln('Scheduled that day:');
      for (final event in sameDay) {
        buffer.writeln('- ${event.label()}');
      }
      return buffer.toString().trimRight();
    },
  );
}

/// Tool: summarize-the-inbox from user-picked mbox files.
///
/// Read-only and offline: local mail the user picked, never a server.
/// Sensitive so the registry asks first.
ToolEntry buildInboxTool({required List<String> Function() mboxPaths}) {
  return ToolEntry(
    definition: const ToolDefinition(
      name: 'summarize_inbox',
      description:
          'Lists recent subjects of the mailbox files the user added. '
          'Read-only and offline; nothing is fetched.',
      risk: ToolRiskLevel.sensitive,
      timeout: Duration(seconds: 10),
      parameters: [
        ToolParameter(
          name: 'limit',
          type: ToolParameterType.integer,
          description: 'How many recent subjects to list.',
          required: false,
          minimum: 1,
          maximum: 10,
        ),
      ],
    ),
    handler: (arguments) async {
      final paths = mboxPaths();
      if (paths.isEmpty) {
        return 'No mailbox is connected. The user can add an mbox file in Settings › Connections.';
      }
      final limit = arguments['limit'] as int? ?? 5;
      final subjects = <String>[];
      for (final path in paths.take(3)) {
        try {
          final content = await File(path).readAsString();
          final messages = WebFetchService.parseMbox(content);
          for (final message in messages.reversed.take(limit)) {
            final subject = message.subject.trim();
            if (subject.isNotEmpty) subjects.add(subject);
            if (subjects.length >= limit) break;
          }
        } catch (_) {
          // One unreadable file must not hide the others.
        }
        if (subjects.length >= limit) break;
      }
      if (subjects.isEmpty) {
        return 'No subjects were found in the connected mailbox files.';
      }
      final buffer = StringBuffer()..writeln('Recent subjects:');
      for (var i = 0; i < subjects.length; i++) {
        buffer.writeln('[${i + 1}] ${subjects[i]}');
      }
      return buffer.toString().trimRight();
    },
  );
}
