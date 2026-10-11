import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart';

/// Mounts the composer card the way a chat does.
Future<void> pumpComposer(
  WidgetTester tester, {
  VoidCallback? onMicPressed,
  ComposerMicState micState = ComposerMicState.idle,
  bool enabled = true,
  required Future<void> Function() onSend,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatComposer(
          controller: TextEditingController(),
          enabled: enabled,
          hintText: 'Ask anything',
          onSend: onSend,
          onMicPressed: onMicPressed,
          micState: micState,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the mic starts dictation without leaving the chat', (
    tester,
  ) async {
    var taps = 0;
    await pumpComposer(tester, onMicPressed: () => taps++, onSend: () async {});

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('an open dictation keeps a tappable mic, because the tap is '
      'what finishes it', (tester) async {
    var taps = 0;
    await pumpComposer(
      tester,
      onMicPressed: () => taps++,
      micState: ComposerMicState.active,
      onSend: () async {},
    );

    // A spinner here would be a dead end: nothing could end the recording.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('a clip being transcribed replaces the mic with a spinner', (
    tester,
  ) async {
    var taps = 0;
    await pumpComposer(
      tester,
      onMicPressed: () => taps++,
      micState: ComposerMicState.transcribing,
      onSend: () async {},
    );

    expect(find.byIcon(Icons.mic_rounded), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // There is nothing to press while the clip is turned into words.
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    expect(taps, 0);
  });

  testWidgets('a composer with nowhere to send voice hides the mic', (
    tester,
  ) async {
    await pumpComposer(tester, onSend: () async {});

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
  });

  testWidgets('a locked composer disables the mic instead of dictating', (
    tester,
  ) async {
    var taps = 0;
    await pumpComposer(
      tester,
      enabled: false,
      onMicPressed: () => taps++,
      onSend: () async {},
    );

    await tester.tap(find.byIcon(Icons.mic_none_rounded), warnIfMissed: false);
    await tester.pump();

    expect(taps, 0);
  });
}
