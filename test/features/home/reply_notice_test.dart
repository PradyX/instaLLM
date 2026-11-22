import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/home/domain/reply_notice.dart';

void main() {
  group('ReplyNotice.excerpt', () {
    test('keeps a short answer as it was written', () {
      expect(
        ReplyNotice.excerpt('The latest Android version is 17 [3].'),
        'The latest Android version is 17 [3].',
      );
    });

    test('flattens markdown the shade would show as punctuation', () {
      const reply = '''
## Summary
The app is **ready** to use, see [the notes](https://example.com/notes).

- `flutter test` passes
- one more line''';
      final excerpt = ReplyNotice.excerpt(reply);
      expect(excerpt, contains('Summary'));
      expect(excerpt, contains('ready'));
      expect(excerpt, contains('the notes'));
      expect(excerpt, contains('flutter test passes'));
      expect(excerpt, isNot(contains('**')));
      expect(excerpt, isNot(contains('https://example.com')));
      expect(excerpt, isNot(contains('##')));
      expect(excerpt, isNot(contains('\n')));
    });

    test('cuts a long answer at a word boundary inside the limit', () {
      final reply = List.filled(60, 'sentence').join(' ');
      final excerpt = ReplyNotice.excerpt(reply);
      expect(excerpt.length, lessThanOrEqualTo(ReplyNotice.excerptLimit + 1));
      expect(excerpt.endsWith('…'), isTrue);
      expect(excerpt.substring(0, excerpt.length - 1).endsWith(' '), isFalse);
      expect(excerpt, isNot(contains('sentence…sentence')));
    });

    test('never invents words for an answer that has none', () {
      expect(ReplyNotice.excerpt(''), '');
      expect(ReplyNotice.excerpt('   \n  '), '');
      expect(ReplyNotice.excerpt('```dart\nfinal x = 1;\n```'), '');
    });

    test('drops a fenced code block but keeps the prose around it', () {
      const reply =
          'Here it is:\n\n```dart\nvoid main() {}\n```\n\nThat is all.';
      expect(ReplyNotice.excerpt(reply), 'Here it is: That is all.');
    });
  });

  group('ReplyNotice.shouldAnnounce', () {
    bool announce({
      AppLifecycleState? lifecycle = AppLifecycleState.paused,
      bool conversationVisible = true,
      bool fromScheduledJob = false,
    }) {
      return ReplyNotice.shouldAnnounce(
        lifecycle: lifecycle,
        conversationVisible: conversationVisible,
        fromScheduledJob: fromScheduledJob,
      );
    }

    test('announces a reply that finished while the app was away', () {
      expect(announce(lifecycle: AppLifecycleState.paused), isTrue);
      expect(announce(lifecycle: AppLifecycleState.inactive), isTrue);
      expect(announce(lifecycle: AppLifecycleState.hidden), isTrue);
    });

    test('says nothing while the user is looking at the conversation', () {
      expect(
        announce(
          lifecycle: AppLifecycleState.resumed,
          conversationVisible: true,
        ),
        isFalse,
      );
    });

    test('announces in the foreground only for another conversation', () {
      expect(
        announce(
          lifecycle: AppLifecycleState.resumed,
          conversationVisible: false,
        ),
        isTrue,
      );
    });

    test('leaves a scheduled job to its own run notice', () {
      expect(
        announce(lifecycle: AppLifecycleState.paused, fromScheduledJob: true),
        isFalse,
      );
    });

    test('treats an unknown lifecycle as foreground', () {
      expect(announce(lifecycle: null, conversationVisible: true), isFalse);
      expect(announce(lifecycle: null, conversationVisible: false), isTrue);
    });
  });

  group('ReplyNotice payload', () {
    test('round-trips a conversation id', () {
      final payload = ReplyNotice.payloadFor('c-mwsb53gk098wxr');
      expect(payload, 'chat:c-mwsb53gk098wxr');
      expect(ReplyNotice.conversationIdFrom(payload), 'c-mwsb53gk098wxr');
    });

    test('ignores other notices and empty ids', () {
      expect(ReplyNotice.conversationIdFrom('job:t-1'), isNull);
      expect(ReplyNotice.conversationIdFrom('chat:'), isNull);
      expect(ReplyNotice.conversationIdFrom(''), isNull);
    });
  });
}
