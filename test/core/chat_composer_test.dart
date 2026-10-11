import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart';

/// Mounts the composer card the way a chat does.
Future<void> pumpComposer(
  WidgetTester tester, {
  VoidCallback? onMicPressed,
  bool isTranscribing = false,
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
          isTranscribing: isTranscribing,
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

  testWidgets('a running dictation replaces the mic with a spinner', (
    tester,
  ) async {
    var taps = 0;
    await pumpComposer(
      tester,
      onMicPressed: () => taps++,
      isTranscribing: true,
      onSend: () async {},
    );

    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // There is nothing to press while the clip transcribes.
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
