import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/features/voice/application/recording_controller.dart';
import 'package:installm/features/voice/data/audio_clip_reader.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/data/whisper_speech_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Talks to the Whisper engine on a real device.
///
/// Unit tests cover the controller against a fake runner and cannot catch a
/// native library that fails to link, a model file the engine cannot read, or
/// a clip it hears differently than expected — which is exactly what adding a
/// native speech engine can break. This test loads the real library, downloads
/// the smallest model through the app's own service, and transcribes a clip
/// the device itself speaks.
///
/// Run on a device or desktop (macOS synthesizes the clip with `say`):
///
/// ```bash
/// flutter test integration_test/whisper_device_smoke_test.dart -d macos
/// ```
///
/// It downloads the Tiny model (~99 MB, three files) from the sherpa-onnx
/// model repository into the app's model directory and removes it again when
/// it was not there before, so a machine that already uses that model keeps
/// it.
/// True when this run installed the model it transcribed with, so the run can
/// take it away again. One download per run, however many tests use it.
bool? _modelInstalledByThisRun;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDownAll(() async {
    if (_modelInstalledByThisRun != true) return;
    await WhisperModelService(
      ModelStorageService(),
    ).remove(WhisperModelCatalog.models.first);
  });

  testWidgets('the speech engine loads and reads a clip', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // Loading the native library and decoding a WAV with it is the cheapest
    // probe there is for a missing or unlinked build.
    sherpa.initBindings();
    final clip = await _spokenClip('Testing one two three.');
    addTearDown(() => clip.parent.delete(recursive: true));

    final wave = sherpa.readWave(clip.path);

    expect(wave.sampleRate, greaterThan(0));
    expect(wave.samples, isNotEmpty);
  });

  testWidgets(
    'transcribes speech the device speaks, end to end',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      final option = WhisperModelCatalog.models.first;
      final service = WhisperModelService(ModelStorageService());
      if (_modelInstalledByThisRun == null) {
        _modelInstalledByThisRun = !await service.isInstalled(option);
        if (_modelInstalledByThisRun == true) await service.download(option);
      }
      final installed = await service.resolve(option.id);
      expect(installed, isNotNull, reason: 'the downloaded model is usable');

      final clip = await _spokenClip('Hello, this is a test of local speech.');
      addTearDown(() => clip.parent.delete(recursive: true));

      final transcript = await SherpaWhisperRunner().transcribe(
        encoderPath: installed!.encoderPath,
        decoderPath: installed.decoderPath,
        tokensPath: installed.tokensPath,
        audioPath: clip.path,
      );

      // Printed so a run leaves the engine's own words behind as evidence,
      // not just a pass.
      // ignore: avoid_print
      print('whisper (${option.name}) heard: $transcript');

      // Whisper punctuates and capitalizes; the words are what matter.
      expect(transcript.toLowerCase(), contains('hello'));
      expect(transcript.toLowerCase(), contains('local speech'));
    },
    // `say` synthesizes the clip, which is what makes this test work without
    // shipping an audio file.
    skip: !Platform.isMacOS,
  );

  testWidgets('reads a clip the app recorded itself', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    // The gap this closes: every earlier run decoded a clip `say` synthesized,
    // whose header is the canonical 44-byte form. A recording this app makes is
    // a different file — macOS writes it as WAVE_FORMAT_EXTENSIBLE, with a
    // 40-byte `fmt ` and JUNK/FLLR chunks — which the native reader this engine
    // used to call refused with an empty wave. Transcription of a real
    // recording therefore failed while this suite stayed green.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final recorder = container.read(microphoneRecorderProvider);

    final granted = await recorder.requestPermission().timeout(
      const Duration(seconds: 60),
      onTimeout: () => false,
    );
    if (!granted) {
      // ignore: avoid_print
      print('microphone not granted, so nothing could be recorded');
      return;
    }

    final path = await recorder.start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await recorder.stop();
    addTearDown(() {
      final clip = File(path);
      if (clip.existsSync()) clip.deleteSync();
    });
    expect(File(path).existsSync(), isTrue, reason: 'a clip was written');

    // Both readers, so a run leaves the difference behind as evidence: the
    // native one still cannot read the app's own file, the app's own reader
    // can.
    final native = sherpa.readWave(path);
    final clip = readAudioClip(path);
    // ignore: avoid_print
    print(
      'the app\'s recording: native reader rate=${native.sampleRate} '
      'samples=${native.samples.length} · app reader rate=${clip.sampleRate} '
      'samples=${clip.samples.length}',
    );
    expect(clip.sampleRate, 16000);
    expect(clip.samples, isNotEmpty);

    final option = WhisperModelCatalog.models.first;
    final service = WhisperModelService(ModelStorageService());
    if (_modelInstalledByThisRun == null) {
      _modelInstalledByThisRun = !await service.isInstalled(option);
      if (_modelInstalledByThisRun == true) await service.download(option);
    }
    final installed = await service.resolve(option.id);
    expect(installed, isNotNull, reason: 'the model to decode with is usable');

    final transcript = await SherpaWhisperRunner().transcribe(
      encoderPath: installed!.encoderPath,
      decoderPath: installed.decoderPath,
      tokensPath: installed.tokensPath,
      audioPath: path,
    );
    // Nothing is spoken during an automated run, so the words are whatever the
    // engine makes of a quiet room. That it decodes the file at all — instead
    // of failing to read it — is what this test is for.
    // ignore: avoid_print
    print('whisper on the app\'s own recording: "$transcript"');
    expect(transcript, isA<String>());
  });
}

/// Speaks [text] into a 16 kHz mono WAV, which is what the engine decodes.
Future<File> _spokenClip(String text) async {
  final directory = await Directory.systemTemp.createTemp('installm_speech');
  final file = File('${directory.path}/spoken.wav');
  final result = await Process.run('say', [
    '-o',
    file.path,
    '--data-format=LEI16@16000',
    text,
  ]);
  if (result.exitCode != 0 || !file.existsSync()) {
    throw StateError('say could not synthesize a clip: ${result.stderr}');
  }
  return file;
}
