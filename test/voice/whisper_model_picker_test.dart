import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/model_storage_service.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/data/whisper_model_service.dart';
import 'package:installm/features/voice/domain/whisper_model_option.dart';
import 'package:installm/features/voice/presentation/whisper_model_picker.dart';

/// Settings that stay in memory, so the tests never touch secure storage.
class _InMemoryVoiceSettings extends VoiceSettingsNotifier {
  _InMemoryVoiceSettings({String? whisperModelId}) {
    state = state.copyWith(whisperModelId: whisperModelId);
  }

  @override
  Future<void> setWhisperModel(String? modelId) async {
    state = state.copyWith(whisperModelId: modelId);
  }
}

/// Service that records what the sheet asked for and installs instantly, so
/// the picker can be driven without a device or a download.
class _FakeWhisperModelService extends WhisperModelService {
  _FakeWhisperModelService({List<WhisperModelOption> installed = const []})
    : installedOptions = List<WhisperModelOption>.from(installed),
      super(ModelStorageService());

  List<WhisperModelOption> installedOptions;
  final List<String> downloadedIds = <String>[];
  final List<String> removedIds = <String>[];

  @override
  Future<List<InstalledWhisperModel>> installed() async {
    return [
      for (final option in WhisperModelCatalog.models)
        if (installedOptions.contains(option))
          InstalledWhisperModel(
            option: option,
            encoderPath: '/models/${option.encoder.fileName}',
            decoderPath: '/models/${option.decoder.fileName}',
            tokensPath: '/models/${option.tokens.fileName}',
          ),
    ];
  }

  @override
  Future<void> download(
    WhisperModelOption option, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadedIds.add(option.id);
    installedOptions.add(option);
    onProgress?.call(option.approximateBytes, option.approximateBytes);
  }

  @override
  Future<void> remove(WhisperModelOption option) async {
    removedIds.add(option.id);
    installedOptions.remove(option);
  }
}

/// Opens the picker the way the app does — from a tap on its entry point —
/// and settles the sheet's first read of the model directory.
Future<void> _openPicker(
  WidgetTester tester, {
  required _FakeWhisperModelService service,
  String? selectedId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        whisperModelServiceProvider.overrideWithValue(service),
        voiceSettingsProvider.overrideWith(
          (ref) => _InMemoryVoiceSettings(whisperModelId: selectedId),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showWhisperModelPicker(context),
                child: const Text('open picker'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open picker'));
  await tester.pumpAndSettle();
}

void main() {
  final tiny = WhisperModelCatalog.models[0];
  final small = WhisperModelCatalog.models[2];

  testWidgets('lists every model with its size and a download action', (
    tester,
  ) async {
    await _openPicker(tester, service: _FakeWhisperModelService());

    expect(find.text('Whisper models'), findsOneWidget);
    for (final option in WhisperModelCatalog.models) {
      expect(find.text(option.name), findsOneWidget, reason: option.id);
      expect(
        find.textContaining(option.sizeLabel),
        findsWidgets,
        reason: option.id,
      );
    }
    // Nothing is installed, so every row offers a download.
    expect(
      find.text('Download'),
      findsNWidgets(WhisperModelCatalog.models.length),
    );
    expect(find.byTooltip('Remove downloaded model'), findsNothing);
  });

  testWidgets('downloading a model installs it and chooses it', (tester) async {
    final service = _FakeWhisperModelService();
    await _openPicker(tester, service: service);

    // The first row is the smallest model, which is what the picker shows in
    // catalog order.
    await tester.tap(find.text('Download').first);
    await tester.pumpAndSettle();

    expect(service.downloadedIds, [tiny.id]);
    // A first download is what the user wanted to use, so it becomes the
    // chosen model without a second step. Read through the harness button,
    // which outlives the sheet.
    final container = ProviderScope.containerOf(
      tester.element(find.text('open picker')),
    );
    expect(
      container.read(voiceSettingsProvider).whisperModelId,
      tiny.id,
      reason: 'the model that was downloaded is selected',
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(
      find.text('Download'),
      findsNWidgets(WhisperModelCatalog.models.length - 1),
    );
    expect(find.byTooltip('Remove downloaded model'), findsOneWidget);
  });

  testWidgets('an installed model can be chosen, and removal asks first', (
    tester,
  ) async {
    final service = _FakeWhisperModelService(installed: [tiny, small]);
    await _openPicker(tester, service: service, selectedId: tiny.id);

    // Two installed models: one is chosen, the other can be used.
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.text('open picker')),
    );

    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();

    expect(container.read(voiceSettingsProvider).whisperModelId, small.id);
    // Choosing closes the sheet, because the choice is the whole errand.
    expect(find.text('Whisper models'), findsNothing);

    await tester.tap(find.text('open picker'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove downloaded model').last);
    await tester.pumpAndSettle();

    // Deleting a download is destructive, so it is confirmed by name (and the
    // sizes are in the dialog, where the cost of the download is visible).
    expect(find.text('Remove ${small.name}?'), findsOneWidget);
    expect(service.removedIds, isEmpty);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(service.removedIds, isEmpty);

    await tester.tap(find.byTooltip('Remove downloaded model').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(service.removedIds, [small.id]);
    // The removed model is back to offering a download; only Tiny is left
    // installed.
    expect(
      find.text('Download'),
      findsNWidgets(WhisperModelCatalog.models.length - 1),
    );
    expect(find.byTooltip('Remove downloaded model'), findsOneWidget);
  });
}
