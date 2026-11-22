import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/draft_attachments_provider.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

const _photo = SharedAttachment(
  path: '/tmp/photo.jpg',
  mimeType: 'image/jpeg',
  name: 'photo.jpg',
);

const _report = SharedAttachment(
  path: '/tmp/report.pdf',
  mimeType: 'application/pdf',
  name: 'report.pdf',
);

void main() {
  test('staged files wait until the composer takes them', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(draftAttachmentsProvider.notifier);

    expect(container.read(draftAttachmentsProvider), isEmpty);

    notifier.stage([_photo]);
    notifier.stage([_report]);

    expect(container.read(draftAttachmentsProvider), [_photo, _report]);
  });

  test('taking the draft empties it, so a file is staged once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(draftAttachmentsProvider.notifier);

    notifier.stage([_photo, _report]);
    final taken = notifier.take();

    expect(taken, [_photo, _report]);
    expect(container.read(draftAttachmentsProvider), isEmpty);
    expect(notifier.take(), isEmpty);
  });

  test('staging nothing does not notify', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(draftAttachmentsProvider.notifier);
    var notifications = 0;
    container.listen(draftAttachmentsProvider, (_, _) => notifications++);

    notifier.stage(const []);

    expect(notifications, 0);
  });
}
