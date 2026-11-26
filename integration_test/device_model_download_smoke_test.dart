import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/service_providers.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/download_progress_provider.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_page.dart';
import 'package:integration_test/integration_test.dart';

/// Downloads one small catalog model through the model page itself, on a real
/// device, with the real network and the real model directory.
///
/// Unit tests cover the download service against fakes. What they cannot cover
/// is whether the redesigned page still wires its Download button to that
/// service on this platform, whether the file really lands in the app's model
/// folder, and whether the row then reports the model as installed.
///
/// Run on a connected device:
///
/// ```bash
/// flutter test integration_test/device_model_download_smoke_test.dart -d <device>
/// ```
///
/// The model is removed again at the end, so the device is left as it was
/// found. Set `INSTALLM_TEST_KEEP_MODEL=1` to keep the download instead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Liquid AI's smallest entry: a real catalog model, about 216 MB.
  const modelId = 'lfm2-350m';

  testWidgets('the catalog downloads a model on this device', (tester) async {
    final catalogModel = LlmModel.availableModels.firstWhere(
      (model) => model.id == modelId,
    );

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ModelSelectionPage())),
    );
    // The controller reads the catalog and the device profile on arrival.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ModelSelectionPage)),
    );

    LlmModel current() => container
        .read(modelSelectionControllerProvider)
        .models
        .firstWhere((model) => model.id == modelId);

    final alreadyInstalled = current().isDownloaded;
    if (!alreadyInstalled) {
      // Narrow the list to this model's family, so its row is on screen
      // whatever the catalog holds. The row's own action is the one pressed.
      await tester.enterText(find.byType(TextField).first, 'LFM2');
      await tester.pump(const Duration(seconds: 1));

      // The catalog arrives from storage asynchronously, so wait for a row to
      // offer its action instead of assuming the first frame already has one.
      for (var attempt = 0; attempt < 30; attempt++) {
        if (find.text('Download').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      if (find.text('Download').evaluate().isEmpty) {
        final visible = find
            .byType(Text)
            .evaluate()
            .map((element) => (element.widget as Text).data)
            .whereType<String>()
            .take(40)
            .join(' | ');
        // ignore: avoid_print
        print(
          'no download row; models: '
          '${container.read(modelSelectionControllerProvider).models.length}; '
          'visible text: $visible',
        );
      }

      final rowTitle = find.textContaining('LFM2-350M-GGUF');
      expect(rowTitle, findsWidgets, reason: 'the 350M row must be on screen');
      final row = find.ancestor(
        of: rowTitle.first,
        matching: find.byType(InkWell),
      );
      final download = find.descendant(
        of: row.first,
        matching: find.text('Download'),
      );
      expect(
        download,
        findsWidgets,
        reason: 'the row must offer a Download button',
      );
      await tester.tap(download.first);
      await tester.pump(const Duration(seconds: 1));

      var finished = false;
      var lastPercent = -1;
      for (var tick = 0; tick < 300; tick++) {
        await tester.pump(const Duration(seconds: 2));
        final progress = container.read(downloadProgressProvider)[modelId];
        if (progress != null) {
          final percent = (progress.progress * 100).round();
          if (percent != lastPercent && percent % 20 == 0) {
            lastPercent = percent;
            // ignore: avoid_print
            print(
              'download $percent% '
              '(${progress.received} of ${progress.total} bytes)',
            );
          }
        }
        if (current().isDownloaded) {
          finished = true;
          break;
        }
      }
      expect(finished, isTrue, reason: 'the download must finish');
    }

    final installed = current();
    expect(installed.isDownloaded, isTrue);
    final path = await container
        .read(modelStorageServiceProvider)
        .resolveModelPath(installed);
    expect(path, isNotNull);
    final file = File(path!);
    expect(file.existsSync(), isTrue, reason: 'the gguf must be on disk');
    final bytes = file.lengthSync();
    expect(bytes, greaterThan(100 * 1024 * 1024));
    // ignore: avoid_print
    print(
      'installed ${catalogModel.name} (${catalogModel.parameterSize}) at '
      '$path · $bytes bytes',
    );

    if (!alreadyInstalled &&
        Platform.environment['INSTALLM_TEST_KEEP_MODEL'] != '1') {
      await container
          .read(modelSelectionControllerProvider.notifier)
          .deleteModel(installed);
      await tester.pump(const Duration(seconds: 1));
      expect(current().isDownloaded, isFalse);
      // ignore: avoid_print
      print('removed the test download again');
    }
  });
}
