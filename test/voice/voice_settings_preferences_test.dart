import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/domain/speech_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> store;
  late List<String> writes;

  setUp(() {
    store = {};
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          if (call.method == 'read') return store[args['key']];
          if (call.method == 'write') {
            final key = args['key'] as String;
            store[key] = args['value'] as String;
            writes.add(key);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<ProviderContainer> load() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(voiceSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  test(
    'legacy GGUF selection resolves to Whisper and keeps voice choices',
    () async {
      final original = jsonEncode({
        'sttModelId': 'old-gguf-model',
        'sttEngine': 'localModel',
        'whisperModelId': 'tiny',
        'ttsVoiceId': 'Samantha|en-US',
        'ttsRate': 1.25,
        'ttsRateVersion': currentSpeechRateVersion,
        'readRepliesAloud': true,
      });
      store['voice_settings'] = original;

      final container = await load();
      final state = container.read(voiceSettingsProvider);
      expect(state.sttEngine, SttEngine.whisper);
      expect(state.sttModelId, 'old-gguf-model');
      expect(state.whisperModelId, 'tiny');
      expect(state.ttsVoiceId, 'Samantha|en-US');
      expect(state.ttsRate, 1.25);
      expect(state.readRepliesAloud, isTrue);
      expect(store['voice_settings'], original);
      expect(writes, isEmpty);

      await container.read(voiceSettingsProvider.notifier).setTtsRate(1.5);
      final saved = jsonDecode(store['voice_settings']!) as Map;
      expect(saved['sttEngine'], 'whisper');
      expect(saved['sttEngineVersion'], 2);
      expect(saved['sttModelId'], 'old-gguf-model');
      expect(saved['whisperModelId'], 'tiny');
      expect(saved['ttsVoiceId'], 'Samantha|en-US');
      expect(saved['readRepliesAloud'], isTrue);

      final restarted = await load();
      expect(
        restarted.read(voiceSettingsProvider).sttEngine,
        SttEngine.whisper,
      );
      expect(restarted.read(voiceSettingsProvider).ttsRate, 1.5);
    },
  );

  for (final engine in [SttEngine.platform, SttEngine.whisper]) {
    test(
      'keeps an existing ${engine.key} choice across save and restart',
      () async {
        store['voice_settings'] = jsonEncode({'sttEngine': engine.key});
        final container = await load();
        expect(container.read(voiceSettingsProvider).sttEngine, engine);
        await container
            .read(voiceSettingsProvider.notifier)
            .setReadRepliesAloud(true);
        final restarted = await load();
        expect(restarted.read(voiceSettingsProvider).sttEngine, engine);
        expect(restarted.read(voiceSettingsProvider).readRepliesAloud, isTrue);
      },
    );
  }

  for (final engine in [null, 'unknown', 123]) {
    test('partial settings with engine $engine use offline Whisper', () async {
      store['voice_settings'] = jsonEncode({
        'sttEngine': ?engine,
        'ttsVoiceId': 'Samantha|en-US',
        'readRepliesAloud': true,
      });
      final container = await load();
      final state = container.read(voiceSettingsProvider);
      expect(state.sttEngine, SttEngine.whisper);
      expect(state.ttsVoiceId, 'Samantha|en-US');
      expect(state.readRepliesAloud, isTrue);
      expect(writes, isEmpty);
    });
  }

  for (final payload in [null, '{broken', '[]']) {
    test(
      'missing or corrupt settings $payload default offline without rewriting',
      () async {
        if (payload != null) store['voice_settings'] = payload;
        final container = await load();
        expect(
          container.read(voiceSettingsProvider).sttEngine,
          SttEngine.whisper,
        );
        expect(store['voice_settings'], payload);
        expect(writes, isEmpty);
      },
    );
  }
}
