import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/domain/review_finding.dart';

void main() {
  group('findings', () {
    test('reads the format the template asks for', () {
      final findings = ReviewFindings.parse(
        'Here is what I found.\n'
        '1. [high] `lib/a.dart` — The note is written without checking the hash\n'
        '   expectedContent is null, so a second writer wins silently.\n'
        '2. [low] `lib/b.dart` — The heading says Done while work is open\n',
      );

      expect(findings, hasLength(2));
      expect(findings.first.severity, ReviewSeverity.high);
      expect(findings.first.file, 'lib/a.dart');
      expect(findings.first.title, contains('without checking the hash'));
      expect(findings.first.detail, contains('a second writer wins'));
      expect(findings[1].severity, ReviewSeverity.low);
      expect(findings[1].detail, isEmpty);
    });

    test('orders the worst first and numbers what the user typed', () {
      final findings = ReviewFindings.parse(
        '1. [note] `a.dart` — A remark\n'
        '2. [blocker] `b.dart` — Data loss\n'
        '3. [medium] `c.dart` — Missing case\n',
      );

      expect(findings.map((finding) => finding.severity), [
        ReviewSeverity.blocker,
        ReviewSeverity.medium,
        ReviewSeverity.note,
      ]);
      expect(findings.first.line(1), '1. [blocker] `b.dart` — Data loss');
    });

    test('keeps a finding a model tagged in its own words', () {
      final findings = ReviewFindings.parse(
        '- Critical: the delete path is unreachable\n'
        '- nit: heading case\n'
        '- no file mentioned here either\n',
      );

      expect(findings.map((finding) => finding.severity), [
        ReviewSeverity.blocker,
        ReviewSeverity.low,
        ReviewSeverity.note,
      ]);
      expect(findings.first.title, contains('unreachable'));
    });

    test('an answer that found nothing is not a finding', () {
      expect(ReviewFindings.parse('No findings'), isEmpty);
      expect(
        ReviewFindings.parse(
          'Nothing is wrong with these changes. They look correct.',
        ),
        isEmpty,
      );
      expect(ReviewFindings.parse(''), isEmpty);
    });

    test('caps the list and never invents a line', () {
      final many = List.generate(
        30,
        (index) => '${index + 1}. [low] — n$index',
      );
      expect(ReviewFindings.parse(many.join('\n')), hasLength(12));
      expect(ReviewFindings.parse('just prose, no tags at all'), isEmpty);
    });

    test('lists what was reviewed with the hand-off command', () {
      final listing = reviewListing(
        context: 'run run-1 (One)',
        files: const ['lib/a.dart'],
        findings: const [
          ReviewFinding(
            severity: ReviewSeverity.high,
            title: 'Unchecked write',
            file: 'lib/a.dart',
            detail: 'The hash is not compared.',
          ),
        ],
      );

      expect(
        listing,
        contains('Review of run run-1 (One) (1 file: lib/a.dart)'),
      );
      expect(listing, contains('1. [high] `lib/a.dart` — Unchecked write'));
      expect(listing, contains('The hash is not compared.'));
      expect(listing, contains('/review fix 1'));
      // The listing is what `/review fix` reads back, so it round-trips.
      final parsed = ReviewFindings.parse(listing);
      expect(parsed, hasLength(1));
      expect(parsed.single.file, 'lib/a.dart');
      expect(parsed.single.title, 'Unchecked write');
    });

    test('a review with no findings says so without pretending', () {
      final listing = reviewListing(
        context: 'run run-1 (One)',
        files: const ['lib/a.dart'],
        findings: const [],
      );
      expect(listing, contains('No findings.'));
      expect(listing, contains('not a proof that nothing is wrong'));
      expect(ReviewFindings.parse(listing), isEmpty);
    });
  });

  group('the reviewer template', () {
    test('asks for severities and shows both halves of a change', () {
      final task = reviewTask(
        subject: 'run run-1 (One) in this chat',
        files: const [
          ReviewFile(
            relativePath: 'notes/plan.md',
            before: 'Step one.',
            after: 'Step one.\nStep two.',
          ),
          ReviewFile(
            relativePath: 'notes/new.md',
            after: 'Fresh.',
            createdByRun: true,
          ),
        ],
        notes: const ['One file was too large to show.'],
      );

      expect(task, contains('[blocker], [high], [medium], [low] or [note]'));
      expect(task, contains('No findings'));
      expect(task, contains('=== notes/plan.md ==='));
      expect(task, contains('--- before ---'));
      expect(task, contains('Step one.'));
      expect(task, contains('Step two.'));
      expect(task, contains('=== notes/new.md (created by this run) ==='));
      expect(task, contains('One file was too large to show.'));
      // A reviewer is told what it is reviewing, and nothing it must invent.
      expect(task, contains('run run-1 (One) in this chat'));
      expect(task, contains('do not invent code you cannot see'));
    });
  });
}
