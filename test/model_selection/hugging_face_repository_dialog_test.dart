import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/services/hugging_face_repository_service.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/features/model_selection/presentation/hugging_face_repository_dialog.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_page.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';

class _Models extends ModelSelectionController {
  final installed = <String>{};
  final added = <HuggingFaceModelVariant>[];
  Object? addError;
  Completer<void>? adding;
  var checks = 0;
  @override
  ModelSelectionState build() => ModelSelectionState(models: const []);

  @override
  Future<void> refreshStorageInfo() async {}

  @override
  Future<bool> isHfVariantInstalled(HuggingFaceModelVariant variant) async {
    checks++;
    return installed.contains(variant.filePath);
  }

  @override
  Future<void> addModelFromHuggingFaceRepo({
    required HuggingFaceRepository repository,
    required HuggingFaceModelVariant variant,
  }) async {
    added.add(variant);
    if (addError != null) throw addError!;
    if (adding != null) await adding!.future;
  }
}

const _repo = HuggingFaceRepository(
  repoId: 'author/Example-1B-GGUF',
  branch: 'main',
  files: [
    HuggingFaceRepositoryFile(
      path: 'Example-Q4_K_M.gguf',
      sizeBytes: 1024,
      isProjector: false,
      quantization: 'Q4_K_M',
    ),
    HuggingFaceRepositoryFile(
      path: 'Example-Q8_0.gguf',
      sizeBytes: 2048,
      isProjector: false,
      quantization: 'Q8_0',
    ),
  ],
);

class _Repository extends HuggingFaceRepositoryService {
  Completer<HuggingFaceRepository>? fetching;
  Object? error;
  var requests = 0;
  @override
  Future<HuggingFaceRepository> fetchRepository(String repoInput) async {
    requests++;
    if (error != null) throw error!;
    return fetching == null ? _repo : fetching!.future;
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _Models models,
  _Repository service, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [modelSelectionControllerProvider.overrideWith(() => models)],
      child: MaterialApp(
        theme: const MaterialTheme(
          TextTheme(),
          surfaceStyle: SurfaceStyle.translucent,
          accent: AccentColor.purple,
        ).dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(modelSelectionControllerProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () => showDialog<HuggingFaceModelVariant>(
                  context: context,
                  builder: (_) => HuggingFaceRepositoryDialog(
                    controller: models,
                    repositoryService: service,
                  ),
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _browse(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).last, 'author/Example-1B-GGUF');
  await tester.tap(find.text('Browse'));
  await tester.pumpAndSettle();
}

/// Shared with the native smoke test; all model/storage work is isolated.
void registerOpeningLifecycleTest() {
  testWidgets(
    'Add Model opens and closes the Hugging Face dialog without a rendering or disposal error',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            modelSelectionControllerProvider.overrideWith(_Models.new),
          ],
          child: MaterialApp(
            theme: const MaterialTheme(
              TextTheme(),
              surfaceStyle: SurfaceStyle.translucent,
              accent: AccentColor.purple,
            ).dark(),
            home: const ModelSelectionPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse a Hugging Face repository'));
      await tester.pumpAndSettle();
      expect(find.text('Hugging Face repository'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Repository'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Add model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse a Hugging Face repository'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Repository'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void main() {
  registerOpeningLifecycleTest();
  testWidgets(
    'GGUF result list renders; an installed variant is skipped and the selection hands off once',
    (tester) async {
      final models = _Models()..installed.add('Example-Q4_K_M.gguf');
      await _pumpDialog(tester, models, _Repository());
      await _browse(tester);
      expect(find.text('Q4_K_M · Example-Q4_K_M.gguf'), findsOneWidget);
      expect(find.text('Q8_0 · Example-Q8_0.gguf'), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
      models.adding = Completer<void>();
      await tester.tap(find.text('Download'));
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(models.added.single.filePath, 'Example-Q8_0.gguf');
      models.adding!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an all-installed repository disables Download', (tester) async {
    final models = _Models()
      ..installed.addAll(_repo.files.map((file) => file.path));
    await _pumpDialog(tester, models, _Repository());
    await _browse(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Download'))
          .onPressed,
      isNull,
    );
    expect(models.added, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repository and registration errors stay in the dialog and allow retry',
    (tester) async {
      final models = _Models();
      final service = _Repository()
        ..error = const HuggingFaceRepositoryException('Repository not found.');
      await _pumpDialog(tester, models, service);
      await _browse(tester);
      expect(find.text('Repository not found.'), findsOneWidget);
      service.error = null;
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      models.addError = StateError('Registration failed');
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not add this model. Please try again.'),
        findsOneWidget,
      );
      models.addError = null;
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dismissal during a fetch ignores late results and prevents duplicate browse requests',
    (tester) async {
      final models = _Models();
      final service = _Repository()
        ..fetching = Completer<HuggingFaceRepository>();
      await _pumpDialog(tester, models, service);
      await tester.enterText(find.byType(TextField), 'author/Example-1B-GGUF');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(service.requests, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      service.fetching!.complete(_repo);
      await tester.pumpAndSettle();
      expect(models.checks, 0);
      expect(models.added, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'input and results fit a narrow screen, large text and visible keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      await _pumpDialog(tester, _Models(), _Repository(), scale: 2);
      await _browse(tester);
      expect(find.text('Q4_K_M · Example-Q4_K_M.gguf'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
