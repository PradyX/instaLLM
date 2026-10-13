import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/application/composer_dictation_controller.dart';
import 'package:installm/features/voice/application/recording_controller.dart';
import 'package:installm/features/voice/data/platform_speech_service.dart';
import 'package:installm/features/voice/presentation/voice_settings_section.dart';

/// Drives the composer microphone against the real device: the real recorder
/// plugin and the real platform recognizer.
///
/// Unit tests cover the dictation flow against fakes and cannot catch a plugin
/// that is not registered, a microphone the OS refuses, a permission prompt
/// nobody answered or a recognizer that never reports a result — which is
/// exactly where "tapping the mic does nothing" comes from. This test listens
/// only for a moment and plays nothing.
///
/// Run on a device or desktop, with no other instance of the app open:
///
/// ```bash
/// flutter test integration_test/device_dictation_smoke_test.dart -d macos
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// How long a first-use permission prompt is given before the run calls it
  /// unanswered. Answering it on screen is enough to let the test continue.
  const promptWindow = Duration(seconds: 60);

  testWidgets('the real microphone writes a clip on this device', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final container = _container();
    addTearDown(container.dispose);
    final recorder = container.read(microphoneRecorderProvider);

    final granted = await recorder.requestPermission().timeout(
      promptWindow,
      onTimeout: () => false,
    );
    // ignore: avoid_print
    print('microphone permission granted: $granted');
    if (!granted) {
      // The dictation test below asserts how the app reports this; there is
      // nothing to capture here.
      return;
    }

    final path = await recorder.start();
    final file = File(path);
    // A recorder may create the file when the first audio buffer arrives
    // rather than when capture starts, so the wait is part of the check.
    for (var attempt = 0; attempt < 50 && !file.existsSync(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final whileRecording = file.existsSync() ? file.lengthSync() : 0;
    // ignore: avoid_print
    print('clip while recording: $whileRecording bytes');

    await recorder.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final afterStop = file.existsSync() ? file.lengthSync() : 0;
    // ignore: avoid_print
    print('clip after stop: $afterStop bytes at $path');

    expect(
      file.existsSync(),
      isTrue,
      reason: 'the microphone produced no clip at all',
    );
    // A wav header alone is 44 bytes; anything less is not a recording.
    expect(afterStop, greaterThan(44));

    await recorder.deleteRecording(path);
    expect(file.existsSync(), isFalse);
  });

  testWidgets('the composer microphone opens, finishes and never stays stuck', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final container = _container();
    addTearDown(container.dispose);
    final field = TextEditingController();
    addTearDown(field.dispose);
    final controller = container.read(composerDictationProvider.notifier);

    await controller.toggle(field);

    final opened = container.read(composerDictationProvider);
    final clip = container.read(recordingControllerProvider).recordedPath;
    // ignore: avoid_print
    print('after the first tap: stage=${opened.stage.name} clip=$clip');

    // Whatever the device does, the first tap either opens the microphone or
    // explains itself — it never leaves the mic showing work with no way out.
    expect(
      opened.errorMessage == null,
      opened.stage == DictationStage.recording,
    );

    if (opened.stage == DictationStage.recording) {
      await controller.toggle(field);
      final finished = container.read(composerDictationProvider);
      // ignore: avoid_print
      print(
        'after the second tap: stage=${finished.stage.name} '
        'error=${finished.errorMessage} text="${field.text}"',
      );

      // No speech model is installed on this machine, so the expected end is
      // an actionable message; with one installed the words land in the field.
      expect(finished.stage, DictationStage.idle);
      expect(
        finished.errorMessage != null || field.text.trim().isNotEmpty,
        isTrue,
        reason: 'the turn ended without a transcript or a reason',
      );
      if (clip != null) expect(File(clip).existsSync(), isFalse);
    }
  });

  testWidgets('device recognition either opens or says why it cannot', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final listener = container.read(platformSpeechProvider);
    addTearDown(listener.cancel);

    final PlatformSpeechStatus status;
    try {
      status = await container
          .read(platformSttStatusProvider.future)
          .timeout(promptWindow);
    } on TimeoutException {
      // This check only reads the system's answer and never asks for it, so
      // it has no prompt to wait for; a timeout means something is wrong.
      fail(
        'device recognition did not answer within '
        '${promptWindow.inSeconds}s',
      );
    }

    // ignore: avoid_print
    print('device recognition status: ${status.name}');

    final opened = await listener.listen().timeout(promptWindow);
    // ignore: avoid_print
    print('listen(): ${opened.name} (isListening=${listener.isListening})');

    if (status != PlatformSpeechStatus.ready) {
      // A device the system has not allowed must be reported, not asked: the
      // request is what used to abort the app when it was launched from a
      // terminal. Nothing may have been opened.
      expect(opened, status);
      expect(listener.isListening, isFalse);
      return;
    }

    expect(opened, PlatformSpeechStatus.ready);

    final transcript = await listener.stop().timeout(promptWindow);
    // ignore: avoid_print
    print('transcript: "$transcript"');

    // Silence is allowed; a microphone left open is not.
    expect(transcript, isA<String>());
    expect(listener.isListening, isFalse);
  });

  testWidgets('the settings do not offer an ask this launch cannot be granted', (
    tester,
  ) async {
    // The crash this guards against: with the app started by `flutter run`
    // from an IDE, the speech-recognition request belonged to the IDE, whose
    // Info.plist has no speech-recognition description, so macOS aborted the
    // app instead of prompting. This run has the same launch shape, so the
    // settings card must read it as one it cannot ask in — the real card, with
    // the real providers, not a fake.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: const [VoiceSettingsSection()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print(
      'parent process: ${systemParentProcessId()} '
      '(credited to this app: ${canOwnSystemPermissionPrompt()})',
    );
    if (!Platform.isMacOS) return;

    expect(
      canOwnSystemPermissionPrompt(),
      isFalse,
      reason:
          'a test run starts the app from the test runner, so a request '
          'belongs to the runner and not to InstaLLM',
    );
    expect(find.text('Allow device recognition'), findsNothing);
    expect(
      find.textContaining('macOS only shows this prompt to an app it started'),
      findsOneWidget,
      reason: 'the row says what to do instead of offering the ask',
    );
  });
}

/// Dictation container with the offline engine, so the test does not depend on
/// whichever engine the developer last chose in Settings.
ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      voiceSettingsProvider.overrideWith((ref) => _LocalEngineSettings()),
    ],
  );
}

/// Engine choice that stays in memory, so the test dictates with the offline
/// model path without touching the user's stored settings.
class _LocalEngineSettings extends VoiceSettingsNotifier {
  @override
  Future<void> setSttEngine(SttEngine engine) async {
    state = state.copyWith(sttEngine: engine);
  }
}
