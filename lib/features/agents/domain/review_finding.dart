/// Limits that keep one review bounded (Road Map 3 Phase 3.3.4).
///
/// A review is evidence, not an opinion: what the bot may look at is the
/// changes a run made, and they are shown whole or not at all, so the prompt
/// cannot quietly turn into a document.
abstract final class ReviewLimits {
  /// Files one review may show.
  static const int maxFiles = 8;

  /// Characters kept of one file's version.
  static const int maxFileBytes = 8 * 1024;

  /// Characters kept of the whole review, across both versions of every file.
  static const int maxReviewBytes = 24 * 1024;

  /// Findings the listing keeps, most serious first.
  static const int maxFindings = 12;
}

/// How serious a finding is, worst first.
enum ReviewSeverity {
  blocker('Blocker'),
  high('High'),
  medium('Medium'),
  low('Low'),
  note('Note');

  const ReviewSeverity(this.label);

  final String label;

  /// The severity a model's tag names, or null when it is not one of ours.
  static ReviewSeverity? byName(String value) {
    final wanted = value.trim().toLowerCase();
    for (final severity in ReviewSeverity.values) {
      if (severity.name == wanted) return severity;
    }
    // A model that answers in its own words still means something by a tag it
    // repeats: map the common ones rather than dropping the finding.
    return switch (wanted) {
      'critical' || 'severe' || 'urgent' => ReviewSeverity.blocker,
      'error' || 'major' => ReviewSeverity.high,
      'warning' || 'warn' || 'moderate' => ReviewSeverity.medium,
      'minor' || 'nit' || 'nitpick' => ReviewSeverity.low,
      'info' || 'observation' => ReviewSeverity.note,
      _ => null,
    };
  }
}

/// One thing a review found, with the severity it was given.
class ReviewFinding {
  const ReviewFinding({
    required this.severity,
    required this.title,
    this.file,
    this.detail = '',
  });

  final ReviewSeverity severity;

  /// What is wrong, in the reviewer's words.
  final String title;

  /// File the finding is about, when the reviewer named one.
  final String? file;

  /// Why it is wrong and what would fail, when the reviewer said more.
  final String detail;

  /// One numbered line, in the exact form [parseListing] reads back.
  ///
  /// The number is what `/review fix <n>` takes, so the listing the user reads
  /// and the hand-off can never disagree about which finding is which.
  String line(int number) {
    final where = file == null ? '' : '`$file` — ';
    return '$number. [${severity.name}] $where$title';
  }

  /// One line for the room, without the number (used in the hand-off task).
  String get summary => file == null ? title : '$file: $title';
}

/// Turns a reviewer's answer into findings, and findings into what the room
/// shows.
///
/// The format is the one [reviewTask] asks for, but a local model does not
/// always follow instructions, so this reads what it can and keeps the rest as
/// the reviewer's own words rather than dropping a real finding. Nothing is
/// invented: a line that carries no tag is not a finding.
abstract final class ReviewFindings {
  /// `1. [high] rest` or `- [high] rest`.
  static final RegExp _tagged = RegExp(
    r'^\s*(?:[-*]\s*)?(?:\d+[.)]\s*)?\[([A-Za-z]+)\]\s*(.*)$',
  );

  /// `high: rest`, `High — rest` (a tag without brackets).
  static final RegExp _labelled = RegExp(
    r'^\s*(?:[-*]\s*)?(blocker|critical|severe|urgent|high|error|major|'
    r'medium|moderate|warning|warn|low|minor|nit|nitpick|note|info|'
    r'observation)\s*[:—–-]\s+(.*)$',
    caseSensitive: false,
  );

  static final RegExp _bullet = RegExp(r'^\s*[-*]\s*(.*)$');
  static final RegExp _file = RegExp(r'^`([^`]+)`\s*(?:—|-)\s*(.*)$');
  static final RegExp _noFindings = RegExp(
    r'no findings|nothing (?:is )?wrong|looks (?:fine|good|correct)',
    caseSensitive: false,
  );

  /// The findings in a reviewer's [answer], most serious first, capped at
  /// [ReviewLimits.maxFindings].
  static List<ReviewFinding> parse(String answer) {
    final found = <ReviewFinding>[];
    ReviewSeverity severity = ReviewSeverity.note;
    String? file;
    String? title;
    final detail = <String>[];

    void flush() {
      if (title == null) return;
      if (found.length < ReviewLimits.maxFindings) {
        found.add(
          ReviewFinding(
            severity: severity,
            title: title!,
            file: file,
            detail: detail.join('\n').trim(),
          ),
        );
      }
      title = null;
      file = null;
      detail.clear();
    }

    for (final raw in answer.split('\n')) {
      final tagged = _tagged.firstMatch(raw);
      final labelled = tagged == null ? _labelled.firstMatch(raw) : null;
      final tag = tagged?.group(1) ?? labelled?.group(1);
      if (tag != null && ReviewSeverity.byName(tag) != null) {
        flush();
        severity = ReviewSeverity.byName(tag)!;
        final rest = (tagged?.group(2) ?? labelled!.group(2))!.trim();
        final named = _file.firstMatch(rest);
        if (named == null) {
          title = rest;
        } else {
          file = named.group(1);
          title = named.group(2)!.trim();
        }
        continue;
      }
      // A bullet is a new finding even when the model tagged nothing — at the
      // lowest severity, as long as the answer is not the "no findings" one.
      final bullet = _bullet.firstMatch(raw);
      if (bullet != null &&
          bullet.group(1)!.trim().isNotEmpty &&
          !_noFindings.hasMatch(answer)) {
        flush();
        severity = ReviewSeverity.note;
        title = bullet.group(1)!.trim();
        continue;
      }
      if (title != null) {
        final text = raw.trim();
        if (text.isNotEmpty) detail.add(text);
      }
    }
    flush();
    found.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return found
        .where((finding) => finding.title.trim().isNotEmpty)
        .take(ReviewLimits.maxFindings)
        .toList();
  }
}

/// The listing the room posts: what was reviewed, then every finding with the
/// number that hands it to a bot.
String reviewListing({
  required String context,
  required List<String> files,
  required List<ReviewFinding> findings,
}) {
  final buffer = StringBuffer('Review of $context');
  if (files.isNotEmpty) {
    buffer.write(
      ' (${files.length} ${files.length == 1 ? 'file' : 'files'}: '
      '${files.join(', ')})',
    );
  }
  buffer.writeln(':');
  if (findings.isEmpty) {
    buffer.write(
      'No findings. The changes read as they are — this is what the reviewer '
      'answered, not a proof that nothing is wrong.',
    );
    return buffer.toString();
  }
  for (var index = 0; index < findings.length; index++) {
    final finding = findings[index];
    buffer.writeln(finding.line(index + 1));
    if (finding.detail.isNotEmpty) {
      for (final line in finding.detail.split('\n')) {
        buffer.writeln('   $line');
      }
    }
  }
  buffer.write(
    'Next: /review fix 1 hands that finding to a bot as a supervised run, and '
    '/review list shows this again. Severity is the reviewer’s own judgement.',
  );
  return buffer.toString();
}

/// One file a review shows the bot.
///
/// Both halves of a change are shown when the run recorded them, because a
/// reviewer that cannot see what the file said before can only praise the
/// current text.
class ReviewFile {
  const ReviewFile({
    required this.relativePath,
    required this.after,
    this.before,
    this.createdByRun = false,
    this.truncated = false,
  });

  final String relativePath;

  /// What the file holds now.
  final String after;

  /// What it held before the run, when that was recorded.
  final String? before;

  /// True when the run created the file, so there is no before-text.
  final bool createdByRun;

  /// True when a version was cut to fit the review's limits.
  final bool truncated;

  String get heading =>
      '$relativePath${createdByRun ? ' (created by this run)' : ''}';
}

/// The reviewer template: what the bot is asked, and how to answer.
///
/// A review is one ordinary turn of the chat it is typed in — same model, same
/// tools, same permissions — so this is a prompt, not a second agent.
String reviewTask({
  required String subject,
  required List<ReviewFile> files,
  List<String> notes = const [],
}) {
  final buffer = StringBuffer()
    ..writeln(
      'Review the changes below and report only what is really wrong: a bug, '
      'a missing validation, a case that would fail, or a claim the change '
      'does not support.',
    )
    ..writeln()
    ..writeln('Answer with one finding per line, most serious first:')
    ..writeln()
    ..writeln('1. [high] `path/to/file` — what is wrong')
    ..writeln('   the evidence in the change, and what would fail')
    ..writeln()
    ..writeln(
      'Use [blocker], [high], [medium], [low] or [note]. Name the file the '
      'finding is in. If you find nothing, answer exactly "No findings" and '
      'nothing else. Do not restate the change, do not invent code you cannot '
      'see, and do not ask for more files.',
    )
    ..writeln()
    ..writeln('$subject:');
  for (final note in notes) {
    buffer.writeln('- $note');
  }
  for (final file in files) {
    buffer
      ..writeln()
      ..writeln('=== ${file.heading} ===');
    if (file.before != null) {
      buffer
        ..writeln('--- before ---')
        ..writeln(file.before)
        ..writeln('--- after ---');
    }
    buffer.writeln(file.after);
  }
  return buffer.toString().trim();
}
