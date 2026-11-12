import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/companion/application/companion_controller.dart';
import 'package:installm/features/companion/application/companion_transcriber.dart';
import 'package:installm/features/companion/application/companion_turn_runner.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/data/companion_settings_store.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';
import 'package:installm/features/companion/presentation/companion_page.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/voice/application/tts_controller.dart';
import 'package:installm/features/voice/data/microphone_recorder.dart';
import 'package:installm/features/voice/data/platform_tts_service.dart';
import 'package:installm/features/voice/domain/speech_voice.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// Proves the Companion really listens, on this machine's own microphone.
///
/// Two things no widget test can check: that the platform grants the
/// microphone and captures audible sound into a file, and that the page's
/// seven bars are driven by those readings rather than by decoration. The
/// stimulus is the machine's own speech synthesizer (`say`), so the capture has
/// something a human would recognise to listen to.
///
/// Run on this Mac, with InstaLLM quit first:
///
/// ```bash
/// scripts/test_macos.sh integration_test/device_companion_mic_smoke_test.dart
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the microphone captures audible sound and the pill follows it', (
    tester,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('companion-mic-');
    addTearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    // 1. The device on its own, before any UI: permission, a real capture while
    //    the machine talks, and the file read back.
    final recorder = AudioRecorder();
    final permitted = await recorder.hasPermission();
    // ignore: avoid_print
    print('microphone permission: $permitted');
    expect(
      permitted,
      isTrue,
      reason: 'macOS has not granted InstaLLM the microphone',
    );

    final rawPath = p.join(tempDir.path, 'raw.wav');
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: recordingSampleRate,
        numChannels: 1,
      ),
      path: rawPath,
    );

    final dbReadings = <double>[];
    final subscription = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen((amplitude) => dbReadings.add(amplitude.current));

    final speech = await Process.start('say', [
      '-v',
      'Samantha',
      'Testing the Companion microphone. One, two, three, four, five.',
    ]);
    addTearDown(speech.kill);
    await speech.exitCode;
    await Future<void>.delayed(const Duration(seconds: 1));

    await subscription.cancel();
    final rawClip = await recorder.stop();
    await recorder.dispose();

    final rawBytes = rawClip == null
        ? Uint8List(0)
        : await File(rawClip).readAsBytes();
    final peak = _peakSample(rawBytes);
    // ignore: avoid_print
    print(
      'captured ${rawBytes.length} bytes · peak sample $peak/32767 · '
      '${dbReadings.length} dBFS readings '
      '(${dbReadings.isEmpty ? 'none' : '${dbReadings.reduce(math.min)} … ${dbReadings.reduce(math.max)}'})',
    );

    expect(
      rawBytes.length,
      greaterThan(44),
      reason: 'the captured clip has no audio data',
    );
    expect(
      peak,
      greaterThan(0),
      reason: 'the captured clip is digital silence',
    );
    expect(dbReadings, isNotEmpty, reason: 'no amplitude readings arrived');

    final loudestDb = dbReadings.reduce(math.max);
    expect(
      loudestDb,
      greaterThan(microphoneSilenceDb),
      reason:
          'every reading sat under the meter floor, so the bars could not move',
    );

    // 2. The page, with the real recorder: the pill's bars come from the same
    //    stream, so audible speech has to raise them.
    final store = CompanionSettingsStore(
      File(p.join(tempDir.path, 'companion', 'settings.json')),
    )..save(const CompanionSettings(enabled: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companionSettingsStoreProvider.overrideWith((ref) async => store),
          chatModelsProvider.overrideWithValue(const <LlmModel>[]),
          selectedChatModelProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: CompanionPage()),
      ),
    );
    expect(
      await _pumpUntil(tester, () => find.text('Ready').evaluate().isNotEmpty),
      isTrue,
      reason: 'the page never offered the microphone',
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CompanionPage)),
      listen: false,
    );

    final pageSpeech = await Process.start('say', [
      '-v',
      'Samantha',
      'Testing the Companion. Can you hear me now?',
    ]);
    addTearDown(pageSpeech.kill);

    await tester.tap(find.text('Ready'));
    expect(
      await _pumpUntil(
        tester,
        () => container.read(companionControllerProvider).isListening,
      ),
      isTrue,
      reason: 'tapping the pill did not start the capture',
    );

    // Read the meter the page draws, for as long as the machine is speaking.
    final levels = <double>[];
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 60));
      final state = container.read(companionControllerProvider);
      if (state.isListening) levels.add(state.levels.last);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    final meterPeak = levels.isEmpty ? 0.0 : levels.reduce(math.max);
    final moved = levels.where((level) => level > 0).length;
    // ignore: avoid_print
    print(
      'pill readings: ${levels.length} · non-zero $moved · '
      'peak ${meterPeak.toStringAsFixed(3)}',
    );

    expect(levels, isNotEmpty, reason: 'the page never received a level');
    expect(
      moved,
      greaterThan(0),
      reason: 'the bars stayed at zero while the machine was speaking',
    );

    await pageSpeech.exitCode;
    // The pause inside the sentence may already have ended the turn on its
    // own, so stop only if the microphone is still open.
    if (find.text('Listening…').evaluate().isNotEmpty) {
      await tester.tap(find.text('Listening…'));
    }
    // The turn now runs transcription and the model behind it, which this
    // machine may not have set up; what this test owns is that the capture
    // ends, the page leaves listening, and it says something honest about
    // what happened next.
    expect(
      await _pumpUntil(
        tester,
        () => find.text('Listening…').evaluate().isEmpty,
        timeout: const Duration(seconds: 60),
      ),
      isTrue,
      reason: 'stopping did not end the capture',
    );
    // ignore: avoid_print
    print(
      'after stop: ${container.read(companionControllerProvider).phaseLabel} · '
      'exchanges '
      '${container.read(companionControllerProvider).exchanges.length}',
    );
    // The orb animates for ever, so this is a bounded pump, not a settle.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    // Whether the turn can finish depends on the speech and chat models
    // installed here, which this capture test deliberately does not require:
    // all it owns is that the microphone closed and the page said so.
    expect(find.text('Listening…'), findsNothing);
  });

  // The pause and follow-up half of the loop, on the same real microphone.
  registerPauseAndFollowUpTest();
}

/// The same real microphone, but with the language stack faked, so the pause
/// and the follow-up can be asserted without depending on which speech and chat
/// models happen to be installed here.
void registerPauseAndFollowUpTest() {
  testWidgets(
    'a real pause ends the capture and the follow-up reopens the mic',
    (tester) async {
      final tempDir = await Directory.systemTemp.createTemp('companion-pause-');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final store =
          CompanionSettingsStore(
            File(p.join(tempDir.path, 'companion', 'settings.json')),
          )..save(
            const CompanionSettings(
              enabled: true,
              silenceTimeout: Duration(milliseconds: 1200),
            ),
          );
      final transcriber = _RecordingTranscriber('what is the time');
      final runner = _ReplyRunner('It is just after nine.');
      final speech = _QuietSpeechEngine();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            companionSettingsStoreProvider.overrideWith((ref) async => store),
            companionTranscriberProvider.overrideWithValue(transcriber),
            companionTurnRunnerProvider.overrideWithValue(runner),
            speechSynthesisEngineProvider.overrideWithValue(speech),
            chatModelsProvider.overrideWithValue(const <LlmModel>[]),
            selectedChatModelProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: CompanionPage()),
        ),
      );
      expect(
        await _pumpUntil(
          tester,
          () => find.text('Ready').evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'the page never became ready',
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CompanionPage)),
        listen: false,
      );

      await tester.tap(find.text('Ready'));
      expect(
        await _pumpUntil(
          tester,
          () => find.text('Listening…').evaluate().isNotEmpty,
        ),
        isTrue,
        reason: 'the capture never started',
      );

      // Speak, then stop: the pause alone must end the turn, with no tap.
      final speechProcess = await Process.start('say', [
        '-v',
        'Samantha',
        'Testing the Companion pause.',
      ]);
      addTearDown(speechProcess.kill);
      await speechProcess.exitCode;

      expect(
        await _pumpUntil(
          tester,
          () => transcriber.clips.isNotEmpty,
          timeout: const Duration(seconds: 30),
        ),
        isTrue,
        reason: 'the pause did not end the capture',
      );
      // ignore: avoid_print
      print(
        'pause ended the turn · heard "${transcriber.clips.length}" clip(s) · '
        'reply spoken ${speech.spoken.length} time(s)',
      );

      // The answer reopens the microphone on its own.
      expect(
        await _pumpUntil(
          tester,
          () => container.read(companionControllerProvider).isListening,
          timeout: const Duration(seconds: 30),
        ),
        isTrue,
        reason: 'the microphone did not reopen after the answer',
      );
      // ignore: avoid_print
      print('follow-up reopened the microphone');

      // And an unused follow-up closes itself instead of recording the room.
      expect(
        await _pumpUntil(
          tester,
          () =>
              container.read(companionControllerProvider).phase ==
              CompanionPhase.idle,
          timeout: const Duration(seconds: 30),
        ),
        isTrue,
        reason: 'the unused follow-up never closed',
      );
      // ignore: avoid_print
      print('unused follow-up closed itself');
    },
  );
}

/// Pumps real frames until [condition] holds, on the device's own clock.
Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    await tester.pump();
    if (condition()) return true;
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Speech model that answers with fixed words and records the clips it saw.
class _RecordingTranscriber implements CompanionTranscriber {
  _RecordingTranscriber(this.heard);

  final String heard;
  final List<String> clips = [];

  @override
  Future<String> transcribe(String clipPath) async {
    clips.add(clipPath);
    return heard;
  }
}

/// Chat model stand-in: the turn shape is what this test asserts.
class _ReplyRunner implements CompanionTurnRunner {
  _ReplyRunner(this.reply);

  final String reply;

  @override
  Future<String?> answer(String transcript) async => reply;

  @override
  void interrupt() {}
}

/// The device voice, recorded instead of heard.
class _QuietSpeechEngine implements SpeechSynthesisEngine {
  final List<String> spoken = [];

  @override
  Future<void> prepare() async {}

  @override
  Future<List<SpeechVoice>> voices() async => const [];

  @override
  Future<void> speak({
    required String text,
    required double rate,
    SpeechVoice? voice,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}
}

/// Peak absolute 16-bit sample in a wav file, header chunks walked properly.
///
/// A capture that reported levels but wrote an empty or all-zero file would not
/// have recorded anything, so the file itself is measured rather than trusted.
int _peakSample(Uint8List bytes) {
  if (bytes.length < 44) return 0;

  var offset = 12;
  var start = 44;
  var length = bytes.length - 44;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    if (id == 'data') {
      start = offset + 8;
      length = math.min(size, bytes.length - start);
      break;
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }

  var peak = 0;
  for (var index = start; index + 1 < start + length; index += 2) {
    final sample = bytes[index] | (bytes[index + 1] << 8);
    final signed = sample >= 0x8000 ? sample - 0x10000 : sample;
    final magnitude = signed.abs();
    if (magnitude > peak) peak = magnitude;
  }
  return peak;
}
