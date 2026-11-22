import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/conversations/domain/message_attachment.dart';

void main() {
  Message messageWith(List<MessageAttachment> attachments) => Message(
    id: 'm1',
    conversationId: 'c1',
    role: MessageRole.user,
    content: 'Summarize this',
    createdAt: DateTime(2026, 11, 22),
    attachments: attachments,
  );

  test('a document attachment is kept apart from images', () {
    final message = messageWith([
      MessageAttachment.create(
        type: AttachmentType.image,
        path: '/tmp/photo.jpg',
        label: 'photo.jpg',
      ),
      MessageAttachment.create(
        type: AttachmentType.document,
        path: '/tmp/report.pdf',
        label: 'report.pdf',
      ),
    ]);

    expect(message.imageAttachments.single.label, 'photo.jpg');
    expect(message.documentAttachments.single.label, 'report.pdf');
    expect(message.attachments, hasLength(2));
  });

  test('a document attachment survives a JSON round trip', () {
    final attachment = MessageAttachment.create(
      type: AttachmentType.document,
      path: '/data/chat/attachments/c1/m1_report.pdf',
      label: 'report.pdf',
      metadata: const {'sharedFromAnotherApp': true},
    );

    final restored = MessageAttachment.fromJson(attachment.toJson());

    expect(restored.type, AttachmentType.document);
    expect(restored.path, attachment.path);
    expect(restored.label, 'report.pdf');
    expect(restored.metadata['sharedFromAnotherApp'], isTrue);
    expect(restored.id, attachment.id);
  });
}
