import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/artifacts/data/artifact_export_service.dart';
import 'package:installm/features/artifacts/data/scan_note_service.dart';
import 'package:installm/features/vault/domain/vault_paths.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';

void main() {
  group('ArtifactExportService', () {
    test('markdown keeps citations', () {
      final markdown = ArtifactExportService.toMarkdown(
        title: 'Plan',
        lines: const [
          ExportLine(role: 'assistant', text: 'Do this.'),
          ExportLine(role: 'user', text: 'Thanks.'),
        ],
        citations: ['notes.md · Setup'],
      );
      expect(markdown, contains('# Plan'));
      expect(markdown, contains('Do this.'));
      expect(markdown, contains('## Sources'));
      expect(markdown, contains('notes.md · Setup'));
    });

    test('slides outline skips non-assistant lines', () {
      final outline = ArtifactExportService.toSlidesOutline(
        title: 'Deck',
        lines: const [
          ExportLine(role: 'user', text: 'Question'),
          ExportLine(role: 'assistant', text: 'First\nSecond'),
        ],
      );
      expect(outline, contains('## Slide 1'));
      expect(outline, contains('- First'));
      expect(outline, contains('- Second'));
      expect(outline.contains('Question'), isFalse);
    });
  });

  group('ScanNoteService', () {
    test('scan lands as an editable note with the image beside it', () async {
      final temp = await Directory.systemTemp.createTemp('scan_note');
      try {
        final vaultRoot = Directory('${temp.path}/vault');
        final image = File('${temp.path}/page.jpg');
        await image.writeAsBytes(List.filled(100, 1));
        final paths = VaultPaths(
          vaultRoot: vaultRoot.path,
          projectPath: 'Scans',
        );
        final service = const ScanNoteService();
        final note = await service.scanToNote(
          paths: paths,
          imagePath: image.path,
          title: 'Receipt',
          permissions: VaultPermissions.defaults,
        );
        expect(note, isNotNull);
        final noteFile = File('${vaultRoot.path}/Scans/$note');
        expect(noteFile.existsSync(), isTrue);
        final content = await noteFile.readAsString();
        expect(content, contains('# Receipt'));
        expect(content, contains('.jpg'));
        // Editable: the note is plain Markdown on disk.
        await noteFile.writeAsString('$content\nExtra line.\n');
        expect(await noteFile.readAsString(), contains('Extra line.'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('missing image refuses without writing', () async {
      final temp = await Directory.systemTemp.createTemp('scan_missing');
      try {
        final paths = VaultPaths(vaultRoot: temp.path, projectPath: 'Scans');
        final note = await const ScanNoteService().scanToNote(
          paths: paths,
          imagePath: '${temp.path}/absent.jpg',
          title: 'Nothing',
          permissions: VaultPermissions.defaults,
        );
        expect(note, isNull);
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });
}
