import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

void main() {
  test('a shared link is read as text', () {
    final payload = sharedPayloadFromMap({
      'text': '  https://example.com/story  ',
      'attachments': const [],
    });

    expect(payload, isNotNull);
    expect(payload!.text, 'https://example.com/story');
    expect(payload.attachments, isEmpty);
    expect(payload.isEmpty, isFalse);
  });

  test('a shared image and PDF are both kept, with their names', () {
    final payload = sharedPayloadFromMap({
      'text': null,
      'attachments': [
        {
          'path': '/data/user/0/com.prady.installm/files/shared/1-photo.jpg',
          'mimeType': 'image/jpeg',
          'name': 'photo.jpg',
        },
        {
          'path': '/data/user/0/com.prady.installm/files/shared/2-report.pdf',
          'mimeType': 'application/pdf',
          'name': 'report.pdf',
        },
      ],
    });

    expect(payload, isNotNull);
    expect(payload!.text, isNull);
    expect(payload.images.single.name, 'photo.jpg');
    expect(payload.documents.single.name, 'report.pdf');
  });

  test('a file kind the composer cannot show is dropped', () {
    final payload = sharedPayloadFromMap({
      'attachments': [
        {
          'path': '/tmp/archive.zip',
          'mimeType': 'application/zip',
          'name': 'archive.zip',
        },
        {'path': '/tmp/song.mp3', 'mimeType': 'audio/mpeg', 'name': 'song.mp3'},
      ],
    });

    expect(payload, isNull);
  });

  test('a partly readable payload keeps only what it can use', () {
    final payload = sharedPayloadFromMap({
      'attachments': [
        {'mimeType': 'image/png', 'name': 'no-path.png'},
        {'path': '/tmp/cat.png', 'name': 'cat.png'},
        {'path': '  ', 'mimeType': 'image/png'},
        {'path': '/tmp/dog.png', 'mimeType': 'image/png'},
      ],
    });

    expect(payload, isNotNull);
    expect(payload!.attachments, hasLength(1));
    expect(payload.attachments.single.path, '/tmp/dog.png');
    // A name the platform did not give falls back to the file name.
    expect(payload.attachments.single.name, 'dog.png');
  });

  test(
    'an editable selection is a process-text request that can be replaced',
    () {
      final payload = sharedPayloadFromMap({
        'text': 'Selected paragraph',
        'attachments': const [],
        'processTextReadOnly': false,
      });

      expect(payload!.text, 'Selected paragraph');
      expect(payload.isProcessText, isTrue);
      expect(payload.canReturnText, isTrue);
    },
  );

  test('a read-only selection is a process-text request that must not be '
      'replaced', () {
    final payload = sharedPayloadFromMap({
      'text': 'Selected paragraph',
      'processTextReadOnly': true,
    });

    expect(payload!.isProcessText, isTrue);
    expect(payload.canReturnText, isFalse);
  });

  test('a share is not a process-text request, and a missing flag is not '
      'invented', () {
    final share = sharedPayloadFromMap({'text': 'https://example.com'});
    expect(share!.isProcessText, isFalse);
    expect(share.canReturnText, isFalse);

    final malformed = sharedPayloadFromMap({
      'text': 'Selected paragraph',
      'processTextReadOnly': 'yes please',
    });
    expect(malformed!.isProcessText, isFalse);
  });

  test('nothing shared reads as no payload at all', () {
    expect(sharedPayloadFromMap(null), isNull);
    expect(sharedPayloadFromMap('text'), isNull);
    expect(sharedPayloadFromMap(const {}), isNull);
    expect(
      sharedPayloadFromMap({'text': '   ', 'attachments': const []}),
      isNull,
    );
  });
}
