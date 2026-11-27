import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/utils/llm_prompt_utils.dart';

/// A model's thought block is shown while it writes and never said out loud,
/// and a local model can only know the date if the prompt carries it.
void main() {
  const open = '<think';
  const close = '</think>';

  group('buildFinalResponseText', () {
    test('keeps only the answer after a closed thought', () {
      expect(
        buildFinalResponseText('$open>planning the reply$close\n\nHello!'),
        'Hello!',
      );
    });

    test('drops a thought that was never closed', () {
      expect(
        buildFinalResponseText('$open>still thinking about the day'),
        'No response generated.',
      );
    });

    test('removes the closing tag a thinking-off prefill leaves', () {
      expect(buildFinalResponseText('$close\n\nHello!'), 'Hello!');
    });
  });

  group('spokenReplyText', () {
    test('reads the answer only', () {
      expect(
        spokenReplyText('$open>planning$close\n\nHello there.'),
        'Hello there.',
      );
    });

    test('says nothing for a bare opening tag', () {
      expect(spokenReplyText('$open Okay, the user is asking'), '');
    });

    test('says nothing while the chat is still thinking', () {
      expect(spokenReplyText('Thinking...\nthe user asked a question'), '');
    });
  });

  group('withCurrentDateTime', () {
    test('appends the device local date and time', () {
      final prompt = withCurrentDateTime(
        'You are a helpful assistant.',
        now: DateTime(2026, 11, 27, 14, 5),
      );

      expect(
        prompt,
        'You are a helpful assistant.\n\n'
        'Current date and time (device local time): '
        'Friday, 27 November 2026 at 14:05.',
      );
    });

    test('a prompt with no persona still carries the date', () {
      expect(
        withCurrentDateTime('', now: DateTime(2026, 1, 2, 3, 4)),
        'Current date and time (device local time): '
        'Friday, 2 January 2026 at 03:04.',
      );
    });
  });
}
