import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/share_inbox.dart';
import 'package:installm/features/share/domain/shared_content_receiver.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

class _FakeReceiver implements SharedContentReceiver {
  _FakeReceiver({this.initial});

  final SharedPayload? initial;
  void Function(SharedPayload payload)? listener;
  var initialRead = false;

  @override
  Future<SharedPayload?> takeInitial() async {
    initialRead = true;
    return initial;
  }

  @override
  void listen(void Function(SharedPayload payload) onPayload) {
    listener = onPayload;
  }

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {}
}

void main() {
  test('a share that launched the app is staged once', () async {
    final staged = <SharedPayload>[];
    final receiver = _FakeReceiver(
      initial: const SharedPayload(text: 'https://example.com/article'),
    );

    await ShareInbox(receiver: receiver, onPayload: staged.add).start();

    expect(staged.single.text, 'https://example.com/article');
  });

  test('a normal launch stages nothing', () async {
    final staged = <SharedPayload>[];
    final receiver = _FakeReceiver();

    await ShareInbox(receiver: receiver, onPayload: staged.add).start();

    expect(receiver.initialRead, isTrue);
    expect(staged, isEmpty);
  });

  test('a share arriving while running is staged, and the listener is live '
      'before the launch payload is read', () async {
    final staged = <SharedPayload>[];
    final receiver = _FakeReceiver(initial: const SharedPayload(text: 'first'));
    var listeningWhenInitialRead = false;

    await ShareInbox(receiver: receiver, onPayload: staged.add).start();
    listeningWhenInitialRead = receiver.listener != null;

    receiver.listener!(
      const SharedPayload(
        attachments: [
          SharedAttachment(
            path: '/tmp/report.pdf',
            mimeType: 'application/pdf',
            name: 'report.pdf',
          ),
        ],
      ),
    );

    expect(listeningWhenInitialRead, isTrue);
    expect(staged, hasLength(2));
    expect(staged.first.text, 'first');
    expect(staged.last.attachments.single.name, 'report.pdf');
  });
}
