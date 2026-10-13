import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/data/platform_speech_service.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/presentation/voice_settings_section.dart';

/// The platform recognizer, faked: these tests are about whether the settings
/// are allowed to ask, not about what the system answers.
class _FakePlatformSpeech implements PlatformSpeechListener {
  _FakePlatformSpeech({required this.state, required this.answer});

  /// What a check reports without asking for anything. A granted request
  /// becomes the new state, the way the real service remembers one.

  /// What an explicit ask reports.
  final PlatformSpeechStatus answer;

  PlatformSpeechStatus state;

  /// How many times the settings asked the system.
  int asks = 0;

  @override
  Future<PlatformSpeechStatus> status() async => state;

  @override
  Future<PlatformSpeechStatus> requestAuthorization() async {
    asks++;
    if (answer == PlatformSpeechStatus.ready) state = answer;
    return answer;
  }

  @override
  Future<PlatformSpeechStatus> listen() async => state;

  @override
  Future<String> stop() async => '';

  @override
  Future<void> cancel() async {}

  @override
  bool get isListening => false;

  @override
  String? get lastError => null;
}

/// Settings that stay in memory, so the tests never touch secure storage.
class _InMemoryVoiceSettings extends VoiceSettingsNotifier {
  @override
  Future<void> setSttEngine(SttEngine engine) async {
    state = state.copyWith(sttEngine: engine);
  }
}

/// No Whisper models, and no model directory to read.
class _NoWhisperModels extends WhisperModelService {
  _NoWhisperModels() : super(ModelStorageService());

  @override
  Future<List<InstalledWhisperModel>> installed() async => const [];
}

/// Pumps the voice settings card with the device recognizer reporting
/// [state], in a launch the system does ([canAsk]) or does not credit for a
/// permission request.
Future<_FakePlatformSpeech> _pumpSettings(
  WidgetTester tester, {
  required bool canAsk,
  PlatformSpeechStatus state = PlatformSpeechStatus.notAuthorized,
  PlatformSpeechStatus answer = PlatformSpeechStatus.notAuthorized,
}) async {
  // Room for the whole card, so the button under test is on screen.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final speech = _FakePlatformSpeech(state: state, answer: answer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceSettingsProvider.overrideWith((ref) => _InMemoryVoiceSettings()),
        platformSpeechProvider.overrideWithValue(speech),
        systemPermissionPromptOwnershipProvider.overrideWithValue(canAsk),
        whisperModelServiceProvider.overrideWithValue(_NoWhisperModels()),
      ],
      child: const MaterialApp(home: Scaffold(body: VoiceSettingsSection())),
    ),
  );
  await tester.pumpAndSettle();
  return speech;
}

void main() {
  testWidgets(
    'a launch another program started is told why, and is never asked',
    (tester) async {
      final speech = await _pumpSettings(tester, canAsk: false);

      // Offering the ask here is what used to end the app: macOS reads the
      // launcher's usage description and aborts instead of prompting.
      expect(find.text('Allow device recognition'), findsNothing);
      expect(
        find.textContaining(
          'macOS only shows this prompt to an app it started',
        ),
        findsOneWidget,
        reason: 'the row explains why it cannot be allowed here',
      );
      expect(speech.asks, 0);
    },
  );

  testWidgets('a launch the system started offers the ask, and reports it', (
    tester,
  ) async {
    final speech = await _pumpSettings(
      tester,
      canAsk: true,
      answer: PlatformSpeechStatus.ready,
    );

    expect(
      find.textContaining('Not allowed yet: allow it below'),
      findsOneWidget,
    );

    await tester.tap(find.text('Allow device recognition'));
    await tester.pumpAndSettle();

    expect(speech.asks, 1);
    expect(find.text('Device recognition is allowed now.'), findsOneWidget);
    // The device is allowed now, so the row no longer explains a limit.
    expect(find.textContaining('Not allowed yet'), findsNothing);
  });

  testWidgets('a device that is already allowed is not offered an ask', (
    tester,
  ) async {
    final speech = await _pumpSettings(
      tester,
      canAsk: true,
      state: PlatformSpeechStatus.ready,
    );

    expect(find.text('Allow device recognition'), findsNothing);
    expect(speech.asks, 0);
    expect(find.text('Local speech model'), findsNothing);
    expect(find.text('Speech model'), findsNothing);
    expect(find.text('Voice conversation'), findsNothing);
    expect(find.text('Whisper model'), findsOneWidget);

    final context = tester.element(find.byType(VoiceSettingsSection));
    final container = ProviderScope.containerOf(context);
    expect(container.read(voiceSettingsProvider).sttEngine, SttEngine.whisper);

    await tester.tap(find.text('Device recognition'));
    await tester.pumpAndSettle();
    expect(container.read(voiceSettingsProvider).sttEngine, SttEngine.platform);
    expect(find.text('Whisper model'), findsNothing);

    await tester.tap(find.text('Whisper'));
    await tester.pumpAndSettle();
    expect(container.read(voiceSettingsProvider).sttEngine, SttEngine.whisper);
    expect(find.text('Whisper model'), findsOneWidget);
    expect(speech.asks, 0);
  });
}
