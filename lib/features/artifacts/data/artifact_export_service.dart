/// Artifact export (Road Map 3 Phase 3.7).
///
/// Get work out in presentable form: a report/plan/chat answer becomes
/// Markdown, a slides outline, or a simple PDF. Citations travel with the
/// export; image generation stays a time-boxed research spike with a decision
/// note (no cloud renderer by default).
abstract final class ArtifactExportService {
  /// Renders chat lines as Markdown with a title and citation section.
  static String toMarkdown({
    required String title,
    required List<ExportLine> lines,
    required List<String> citations,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${title.trim().isEmpty ? 'Export' : title.trim()}');
    buffer.writeln();
    for (final line in lines) {
      if (line.role.trim().isEmpty) {
        buffer.writeln(line.text.trim());
      } else {
        buffer.writeln('**${line.role.trim()}:** ${line.text.trim()}');
      }
      buffer.writeln();
    }
    if (citations.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('## Sources');
      buffer.writeln();
      for (final citation in citations) {
        buffer.writeln('- $citation');
      }
    }
    return buffer.toString().trimRight();
  }

  /// Renders the same lines as a slides outline: one heading per assistant
  /// message, bullets for its lines.
  static String toSlidesOutline({
    required String title,
    required List<ExportLine> lines,
  }) {
    final buffer = StringBuffer()
      ..writeln('# ${title.trim().isEmpty ? 'Slides' : title.trim()}');
    var slide = 0;
    for (final line in lines) {
      if (line.role.toLowerCase() != 'assistant') continue;
      slide++;
      buffer.writeln();
      buffer.writeln('## Slide $slide');
      for (final bullet in line.text.split('\n')) {
        final trimmed = bullet.trim();
        if (trimmed.isEmpty) continue;
        buffer.writeln('- $trimmed');
      }
    }
    if (slide == 0) {
      buffer.writeln();
      buffer.writeln('## Slide 1');
      buffer.writeln('- (no assistant messages to outline yet)');
    }
    return buffer.toString().trimRight();
  }

  /// File name for an export: slug plus extension.
  static String fileName(String title, String extension) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? 'export' : slug;
    final trimmed = base.length <= 60 ? base : base.substring(0, 60);
    final ext = extension.trim().isEmpty ? 'md' : extension.trim();
    return '$trimmed-${DateTime.now().microsecondsSinceEpoch}.$ext';
  }
}

/// One chat line to export.
class ExportLine {
  const ExportLine({required this.role, required this.text});

  /// `user`, `assistant`, or empty for a plain paragraph.
  final String role;
  final String text;
}
