import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/share_inbox.dart';
import 'package:installm/features/share/domain/shared_text_receiver.dart';

class _FakeReceiver implements SharedTextReceiver {
  _FakeReceiver({this.initial});

  final String? initial;
  void Function(String text)? listener;
  var initialRead = false;

  @override
  Future<String?> takeInitial() async {
    initialRead = true;
    return initial;
  }

  @override
  void listen(void Function(String text) onText) {
    listener = onText;
  }

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {}
}

void main() {
  test('a share that launched the app is staged once', () async {
    final staged = <String>[];
    final receiver = _FakeReceiver(initial: '  https://example.com/article  ');

    await ShareInbox(receiver: receiver, onText: staged.add).start();

    expect(staged, ['https://example.com/article']);
  });

  test('a normal launch stages nothing', () async {
    final staged = <String>[];
    final receiver = _FakeReceiver();

    await ShareInbox(receiver: receiver, onText: staged.add).start();

    expect(receiver.initialRead, isTrue);
    expect(staged, isEmpty);
  });

  test('a share arriving while running is staged, and the listener is live '
      'before the launch payload is read', () async {
    final staged = <String>[];
    final receiver = _FakeReceiver(initial: 'first');
    var listeningWhenInitialRead = false;

    await ShareInbox(receiver: receiver, onText: staged.add).start();
    listeningWhenInitialRead = receiver.listener != null;

    receiver.listener!('second');

    expect(listeningWhenInitialRead, isTrue);
    expect(staged, ['first', 'second']);
  });
}
