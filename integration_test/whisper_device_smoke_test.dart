import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_llm/core/services/model_storage_service.dart';
import 'package:pocket_llm/features/voice/data/whisper_model_service.dart';
import 'package:pocket_llm/features/voice/data/whisper_speech_service.dart';
import 'package:pocket_llm/features/voice/domain/whisper_model_option.dart';
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
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
      final wasInstalled = await service.isInstalled(option);
      addTearDown(() async {
        if (!wasInstalled) await service.remove(option);
      });

      if (!wasInstalled) {
        await service.download(option);
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
}

/// Speaks [text] into a 16 kHz mono WAV, which is what the engine decodes.
Future<File> _spokenClip(String text) async {
  final directory = await Directory.systemTemp.createTemp('pocket_llm_speech');
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
