import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/connections/domain/connector_config.dart';
import 'package:installm/features/reminders/domain/scheduled_task.dart';

void main() {
  group('ScheduledTask', () {
    test('due only when enabled and time reached', () {
      final now = DateTime(2026, 10, 16, 9);
      final task = ScheduledTask.create(
        title: 'Stretch',
        nextRunAt: now,
        now: now,
      );
      expect(task.isDueAt(now), isTrue);
      expect(task.copyWith(enabled: false).isDueAt(now), isFalse);
      expect(task.isDueAt(now.subtract(const Duration(minutes: 1))), isFalse);
    });

    test('one-shot disables, daily advances past now', () {
      final now = DateTime(2026, 10, 16, 9);
      final once = ScheduledTask.create(
        title: 'Once',
        nextRunAt: now,
        now: now,
      ).firedAt(now);
      expect(once.enabled, isFalse);

      final daily = ScheduledTask.create(
        title: 'Daily',
        nextRunAt: DateTime(2026, 10, 16, 8),
        recurrence: TaskRecurrence.daily,
        now: now,
      ).firedAt(DateTime(2026, 10, 16, 9));
      expect(daily.nextRunAt, DateTime(2026, 10, 17, 8));
      expect(daily.lastFiredAt, DateTime(2026, 10, 16, 9));
    });

    test('corrupt JSON never throws, never invents a task', () {
      expect(ScheduledTask.fromJson({}), isNull);
      expect(ScheduledTask.fromJson({'id': 'x'}), isNull);
    });
  });

  group('ReminderParser', () {
    test('parses in-minutes reminders', () {
      final now = DateTime(2026, 10, 16, 9);
      final draft = ReminderParser.parse(
        'remind me in 10 minutes to stretch',
        now,
      );
      expect(draft, isNotNull);
      expect(draft!.title.toLowerCase(), contains('stretch'));
      expect(draft.nextRunAt, now.add(const Duration(minutes: 10)));
    });

    test('parses every morning with a time', () {
      final now = DateTime(2026, 10, 16, 9);
      final draft = ReminderParser.parse('every morning at 8 standup', now);
      expect(draft, isNotNull);
      expect(draft!.recurrence, TaskRecurrence.daily);
      expect(draft.nextRunAt, DateTime(2026, 10, 17, 8));
    });

    test('ignores non-reminder chat', () {
      expect(
        ReminderParser.parse('what is the plan?', DateTime(2026, 10, 16)),
        isNull,
      );
    });
  });

  group('connectors stay credential-free', () {
    test('config files carry no passwords', () {
      const calendar = CalendarConnector(
        icsPaths: ['/docs/cal.ics'],
        caldavUrl: 'https://cal.example.com',
      );
      expect(calendar.toJson().toString(), isNot(contains('password')));
      expect(calendar.isConfigured, isTrue);

      const email = EmailConnector(
        imapHost: 'imap.example.com',
        imapUser: 'me@example.com',
      );
      expect(email.toJson().toString(), isNot(contains('password')));
      expect(email.isConfigured, isTrue);

      expect(
        EmailConnector.fromJson(const {'imapHost': 'h'}).isConfigured,
        isFalse,
      );
    });

    test('ICS parsing reads local events in order', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'SUMMARY:Standup\r\n'
          'DTSTART:20261017T090000\r\n'
          'END:VEVENT\r\n'
          'BEGIN:VEVENT\r\n'
          'SUMMARY:Dentist\r\n'
          'DTSTART:20261016T150000\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      final events = IcsParser.parse(ics);
      expect(events.map((entry) => entry.summary), ['Dentist', 'Standup']);
      expect(events.first.label(), contains('2026-10-16'));
    });
  });
}
