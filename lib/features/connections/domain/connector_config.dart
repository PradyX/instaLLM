/// Local calendar/email connectors (Road Map 3 Phase 3.6, read-only first).
///
/// User-configured local connectors (CalDAV/ICS files, IMAP/app-password).
/// Read through permission-gated tools; credentials live in secure storage and
/// never in the exported file. Summarize-the-inbox and check-my-day become
/// tool calls, not features.
///
/// This build reads ICS files the user picked and stores IMAP/CalDAV
/// configuration without background sync: the tools report what is configured
/// and read the local files; live server sync stays an explicit fetch.
class CalendarConnector {
  const CalendarConnector({this.icsPaths = const [], this.caldavUrl = ''});

  /// Local ICS files the user picked.
  final List<String> icsPaths;

  /// CalDAV URL when configured (credentials in secure storage, never here).
  final String caldavUrl;

  bool get isConfigured => icsPaths.isNotEmpty || caldavUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'icsPaths': icsPaths,
    'caldavUrl': caldavUrl,
  };

  static CalendarConnector fromJson(Object? raw) {
    if (raw is! Map) return const CalendarConnector();
    final map = Map<String, dynamic>.from(raw);
    final paths = <String>[];
    if (map['icsPaths'] is List) {
      for (final entry in (map['icsPaths'] as List).take(20)) {
        if (entry is String && entry.trim().isNotEmpty) {
          paths.add(entry);
        }
      }
    }
    final url = map['caldavUrl'];
    return CalendarConnector(
      icsPaths: paths,
      caldavUrl: url is String ? url : '',
    );
  }
}

class EmailConnector {
  const EmailConnector({
    this.imapHost = '',
    this.imapUser = '',
    this.mboxPaths = const [],
  });

  /// IMAP host and user when configured (password in secure storage).
  final String imapHost;
  final String imapUser;

  /// Local mbox files the user picked (read directly, no server).
  final List<String> mboxPaths;

  bool get isConfigured =>
      (imapHost.trim().isNotEmpty && imapUser.trim().isNotEmpty) ||
      mboxPaths.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'imapHost': imapHost,
    'imapUser': imapUser,
    'mboxPaths': mboxPaths,
  };

  static EmailConnector fromJson(Object? raw) {
    if (raw is! Map) return const EmailConnector();
    final map = Map<String, dynamic>.from(raw);
    final paths = <String>[];
    if (map['mboxPaths'] is List) {
      for (final entry in (map['mboxPaths'] as List).take(20)) {
        if (entry is String && entry.trim().isNotEmpty) {
          paths.add(entry);
        }
      }
    }
    return EmailConnector(
      imapHost: map['imapHost'] is String ? map['imapHost'] as String : '',
      imapUser: map['imapUser'] is String ? map['imapUser'] as String : '',
      mboxPaths: paths,
    );
  }
}

/// Secure-storage keys for connector secrets. The config file names the
/// server; these keys hold the password.
String imapPasswordKey(String host, String user) =>
    'imap_password_${host.trim().toLowerCase()}_${user.trim().toLowerCase()}';

String caldavPasswordKey(String url, String user) =>
    'caldav_password_${url.trim().toLowerCase().hashCode}_${user.trim().toLowerCase()}';

/// One calendar event of a user-picked ICS file.
class IcsEvent {
  const IcsEvent({
    required this.summary,
    this.start,
    this.end,
    this.description = '',
  });

  final String summary;
  final DateTime? start;
  final DateTime? end;
  final String description;

  /// `2026-10-17 09:00 — Standup`.
  String label() {
    final when = start == null
        ? 'unscheduled'
        : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')} '
              '${start!.hour.toString().padLeft(2, '0')}:${start!.minute.toString().padLeft(2, '0')}';
    return '$when — $summary';
  }
}

/// Best-effort ICS parsing: VEVENT blocks with SUMMARY/DTSTART/DTEND.
/// Local files only, picked by the user — nothing is fetched.
abstract final class IcsParser {
  static List<IcsEvent> parse(String content) {
    final events = <IcsEvent>[];
    final blocks = content.split(RegExp(r'BEGIN:VEVENT', caseSensitive: false));
    for (final block in blocks.skip(1)) {
      final end = block.toUpperCase().indexOf('END:VEVENT');
      final body = end < 0 ? block : block.substring(0, end);
      final fields = _unfold(body);
      final summary = fields['SUMMARY'] ?? '';
      if (summary.trim().isEmpty) continue;
      events.add(
        IcsEvent(
          summary: summary.trim(),
          start: _parseDate(fields['DTSTART']),
          end: _parseDate(fields['DTEND']),
          description: (fields['DESCRIPTION'] ?? '').trim(),
        ),
      );
      if (events.length >= 500) break;
    }
    events.sort((a, b) {
      final x = a.start;
      final y = b.start;
      if (x == null && y == null) return a.summary.compareTo(b.summary);
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return events;
  }

  static Map<String, String> _unfold(String body) {
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final unfolded = <String>[];
    for (final line in lines) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          unfolded.isNotEmpty) {
        unfolded[unfolded.length - 1] += line.substring(1);
      } else {
        unfolded.add(line);
      }
    }
    final fields = <String, String>{};
    for (final line in unfolded) {
      final colon = line.indexOf(':');
      if (colon < 0) continue;
      final name = line
          .substring(0, colon)
          .split(';')
          .first
          .trim()
          .toUpperCase();
      if (name.isEmpty || fields.containsKey(name)) continue;
      fields[name] = line
          .substring(colon + 1)
          .replaceAll(r'\,', ',')
          .replaceAll(r'\n', '\n')
          .trim();
    }
    return fields;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final compact = value.trim().replaceAll('Z', '');
    // YYYYMMDDTHHMMSS or YYYYMMDD.
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?)?$',
    ).firstMatch(compact);
    if (match == null) return DateTime.tryParse(value);
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4) ?? '0'),
        int.parse(match.group(5) ?? '0'),
        int.parse(match.group(6) ?? '0'),
      );
    } catch (_) {
      return null;
    }
  }
}
