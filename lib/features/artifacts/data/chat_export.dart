import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:installm/features/artifacts/data/artifact_export_service.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// What an export writes out (Road Map 5 Phase 5.0).
///
/// The reference app's "document generation" and "export chats" are the same
/// idea from two directions: a conversation becomes a file another program can
/// open. PDF, Markdown, plain text and JSON cover that without adding a writer
/// dependency: PDF comes from `syncfusion_flutter_pdf`, which the document
/// extractor already uses.
enum ChatExportFormat {
  pdf('PDF', 'pdf'),
  markdown('Markdown', 'md'),
  text('Plain text', 'txt'),
  json('JSON', 'json');

  const ChatExportFormat(this.label, this.extension);

  /// Name shown in the menu and in the save dialog's type group.
  final String label;

  /// Extension without the dot.
  final String extension;
}

/// Turns the conversation on screen into an exportable document.
///
/// Pure functions only: the caller owns the save dialog and the file system, so
/// the formatting can be tested without touching a disk. Tool activity, tokens
/// and generation stats are left out — an export is what was said, and the
/// document sources travel as a citation list so an answer keeps its evidence.
abstract final class ChatExport {
  static const Map<MessageRole, String> _roles = {
    MessageRole.user: 'You',
    MessageRole.assistant: 'Assistant',
    MessageRole.system: 'System',
  };

  /// One line per message, in order, skipping messages with no text.
  static List<ExportLine> linesFor(List<Message> messages) {
    return [
      for (final message in messages)
        if (message.content.trim().isNotEmpty)
          ExportLine(
            role: _roles[message.role] ?? 'Message',
            text: message.content,
          ),
    ];
  }

  /// Document sources cited by any answer, in first-seen order and deduplicated
  /// by their printed label.
  static List<String> citationsFor(List<Message> messages) {
    final seen = <String>{};
    for (final message in messages) {
      for (final source in message.sources) {
        seen.add(source.citationLabel);
      }
    }
    return [...seen];
  }

  /// Markdown through the existing artifact renderer, so a document export and
  /// an artifact export read the same.
  static String markdown({
    required String title,
    required List<Message> messages,
  }) {
    return ArtifactExportService.toMarkdown(
      title: title,
      lines: linesFor(messages),
      citations: citationsFor(messages),
    );
  }

  /// Plain text for pasting anywhere: the title, then `You:` / `Assistant:`
  /// paragraphs, then the sources.
  static String text({required String title, required List<Message> messages}) {
    final buffer = StringBuffer()
      ..writeln(title.trim().isEmpty ? 'Chat' : title.trim())
      ..writeln();
    for (final line in linesFor(messages)) {
      buffer
        ..writeln('${line.role}:')
        ..writeln(line.text.trim())
        ..writeln();
    }
    final citations = citationsFor(messages);
    if (citations.isNotEmpty) {
      buffer
        ..writeln('Sources')
        ..writeln();
      for (final citation in citations) {
        buffer.writeln('- $citation');
      }
    }
    return buffer.toString().trimRight();
  }

  /// The conversation's own shape, so the file can be read by hand or by a
  /// later import.
  static String json({
    required String title,
    required List<Message> messages,
    DateTime? exportedAt,
  }) {
    final payload = {
      'title': title.trim().isEmpty ? 'Chat' : title.trim(),
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'messages': [
        for (final message in messages)
          {
            'role': message.role.name,
            'content': message.content,
            'createdAt': message.createdAt.toIso8601String(),
            if (message.modelName != null) 'model': message.modelName,
            if (message.sources.isNotEmpty)
              'sources': [for (final s in message.sources) s.citationLabel],
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// A text-first PDF: bold role headings over wrapped body text, with real
  /// page breaks. Images and tables are not rendered in this phase.
  static Uint8List pdf({
    required String title,
    required List<Message> messages,
  }) {
    final document = PdfDocument();
    var page = document.pages.add();
    var client = page.getClientSize();
    var y = 0.0;

    final headingFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      15,
      style: PdfFontStyle.bold,
    );
    final roleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      10.5,
      style: PdfFontStyle.bold,
    );
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10.5);

    void write(
      String value,
      PdfFont font, {
      double before = 0,
      double after = 2,
    }) {
      if (value.trim().isEmpty) return;
      y += before;
      final lineHeight = font.height;
      for (final line in _wrap(value, font, client.width)) {
        if (y + lineHeight > client.height) {
          page = document.pages.add();
          client = page.getClientSize();
          y = 0;
        }
        if (line.isNotEmpty) {
          page.graphics.drawString(
            line,
            font,
            bounds: Rect.fromLTWH(0, y, client.width, lineHeight),
          );
        }
        y += lineHeight;
      }
      y += after;
    }

    write(title.trim().isEmpty ? 'Chat' : title.trim(), headingFont, after: 10);
    for (final line in linesFor(messages)) {
      write(line.role, roleFont, before: 8, after: 2);
      write(line.text, bodyFont, after: 2);
    }
    final citations = citationsFor(messages);
    if (citations.isNotEmpty) {
      write('Sources', headingFont, before: 14, after: 6);
      for (final citation in citations) {
        write('- $citation', bodyFont);
      }
    }

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  /// Bytes for [format], ready to be written to a file.
  static Uint8List build({
    required ChatExportFormat format,
    required String title,
    required List<Message> messages,
  }) {
    switch (format) {
      case ChatExportFormat.pdf:
        return pdf(title: title, messages: messages);
      case ChatExportFormat.markdown:
        return Uint8List.fromList(
          utf8.encode(markdown(title: title, messages: messages)),
        );
      case ChatExportFormat.text:
        return Uint8List.fromList(
          utf8.encode(text(title: title, messages: messages)),
        );
      case ChatExportFormat.json:
        return Uint8List.fromList(
          utf8.encode(json(title: title, messages: messages)),
        );
    }
  }

  /// A readable file name: the conversation title, then the local time.
  static String fileName({
    required String title,
    required ChatExportFormat format,
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty
        ? 'chat'
        : (slug.length <= 48 ? slug : slug.substring(0, 48));
    final date =
        '${stamp.year}${two(stamp.month)}${two(stamp.day)}-${two(stamp.hour)}${two(stamp.minute)}';
    return '$base-$date.${format.extension}';
  }

  /// Wraps [value] to [maxWidth], keeping explicit newlines as paragraph breaks.
  static List<String> _wrap(String value, PdfFont font, double maxWidth) {
    final lines = <String>[];
    for (final paragraph in value.split('\n')) {
      final words = paragraph
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      if (words.isEmpty) {
        lines.add('');
        continue;
      }
      var current = '';
      for (final word in words) {
        final trial = current.isEmpty ? word : '$current $word';
        if (current.isEmpty || font.measureString(trial).width <= maxWidth) {
          current = trial;
        } else {
          lines.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) lines.add(current);
    }
    return lines;
  }
}
