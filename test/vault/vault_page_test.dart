import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/core/theme/theme.dart';
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/features/vault/application/vault_browser_controller.dart';
import 'package:installm/features/vault/application/vaults_controller.dart';
import 'package:installm/features/vault/data/vault_store.dart';
import 'package:installm/features/vault/domain/vault_registration.dart';
import 'package:installm/features/vault/presentation/vault_page.dart';
import 'package:installm/features/vault/presentation/vaults_page.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/workspaces/data/workspace_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';
import 'package:installm/i18n/strings.g.dart';

class _EmptyModels extends ModelSelectionController {
  @override
  ModelSelectionState build() =>
      ModelSelectionState(models: [], selectedModelId: null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File note;
  late File other;
  late VaultStore store;
  late ProviderContainer container;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('vault-page-');
    note = File('${root.path}/notes/Research/summary.md')
      ..createSync(recursive: true);
    note.writeAsStringSync(
      '# Research summary\n\nUse Dart.\n\n![Sketch](https://example.invalid/private.png)',
    );
    other = File('${root.path}/notes/Other.md')
      ..writeAsStringSync('Keep this note.');
    final workspace = Workspace.create(id: 'w', name: 'Project');
    final workspaces = WorkspaceStore(File('${root.path}/workspaces.json'));
    workspaces.save(
      WorkspacesSnapshot(workspaces: [workspace], activeWorkspaceId: 'w'),
    );
    store = VaultStore(File('${root.path}/registry.json'));
    store.save(
      VaultsSnapshot(
        vaults: [
          VaultRegistration.create(
            id: 'v',
            name: 'Work notes',
            rootPath: '${root.path}/notes',
          ),
        ],
        bindings: const [
          WorkspaceVaultBinding(
            workspaceId: 'w',
            vaultId: 'v',
            projectPath: '',
          ),
        ],
      ),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => root.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        workspaceStoreProvider.overrideWith((ref) async => workspaces),
        vaultStorageProvider.overrideWithValue(
          AppStorageService(
            documentsDirectory: Directory('${root.path}/private'),
            mobile: true,
          ),
        ),
        modelSelectionControllerProvider.overrideWith(_EmptyModels.new),
      ],
    );
    await container.read(vaultsProvider.notifier).whenReady;
    await container.read(workspacesProvider.notifier).whenReady;
    await container.read(vaultStorageProvider).root;
  });
  tearDown(() async {
    container.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    if (root.existsSync()) await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    bool narrow = false,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(narrow ? 320 : 1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = MaterialTheme(ThemeData().textTheme);
    final router = GoRouter(
      initialLocation: AppRoutes.vaults,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const AppShell(
            section: AppSection.chats,
            child: Scaffold(body: Text('Chat destination')),
          ),
        ),
        GoRoute(path: AppRoutes.vaults, builder: (_, _) => const VaultPage()),
        GoRoute(path: '/second-vault', builder: (_, _) => const VaultPage()),
        GoRoute(
          path: AppRoutes.vaultManage,
          builder: (_, _) => const VaultsPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: dark ? theme.dark() : theme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('vault-entry-Research')));
    await flush(tester);
    await tester.tap(
      find.byKey(const ValueKey('vault-entry-Research/summary.md')),
    );
    await flush(tester);
  }

  Finder dialogAction(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  testWidgets(
    'approved split reader edits and saves the actual file without loading images',
    (tester) async {
      await pump(tester);
      await open(tester);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vault-entry-Research/summary.md')),
        findsOneWidget,
      );
      expect(
        tester.allWidgets.whereType<Image>().where(
          (image) => image.image is NetworkImage,
        ),
        isEmpty,
      );
      await tester.tap(find.text(t.vault.edit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault-note-editor')),
        '# Edited\n\nExact Markdown.',
      );
      await tester.tap(find.text(t.vault.save));
      await flush(tester);
      expect(note.readAsStringSync(), '# Edited\n\nExact Markdown.');
      expect(other.readAsStringSync(), 'Keep this note.');
      expect(find.byKey(const ValueKey('vault-note-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Delete confirms removal of only the selected note and Cancel changes nothing',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text(t.vault.delete));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction(t.vault.cancel));
      await tester.pumpAndSettle();
      expect(note.existsSync(), isTrue);
      await tester.tap(find.text(t.vault.delete));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction(t.vault.delete));
      await flush(tester);
      expect(note.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(
        ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('vault-page-scaffold'))),
        ).read(vaultBrowserProvider).note,
        isNull,
      );
      expect(store.load().vaultById('v')?.rootPath, '${root.path}/notes');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'concurrent edits preserve the file and the draft; cancellation and reload are explicit',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text(t.vault.edit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault-note-editor')),
        'My unsaved draft.',
      );
      note.writeAsStringSync('An external edit.');
      await tester.tap(find.text(t.vault.save));
      await flush(tester);
      expect(note.readAsStringSync(), 'An external edit.');
      expect(find.text(t.vault.conflict), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('vault-note-editor')))
            .controller!
            .text,
        'My unsaved draft.',
      );
      await tester.tap(find.byTooltip(t.vault.refresh));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction(t.vault.cancel));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vault-note-editor')), findsOneWidget);
      await tester.tap(find.byTooltip(t.vault.refresh));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction(t.vault.discard));
      await flush(tester);
      expect(
        ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('vault-page-scaffold'))),
        ).read(vaultBrowserProvider).note?.content,
        'An external edit.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager rename persists and removal preserves external files', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(t.vault.manage));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.vault.rename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Renamed notes');
    await tester.tap(dialogAction(t.vault.save));
    await flush(tester);
    expect(store.load().vaultById('v')?.name, 'Renamed notes');
    await tester.tap(find.text(t.vault.remove));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction(t.vault.cancel));
    await tester.pumpAndSettle();
    expect(store.load().vaultById('v'), isNotNull);
    await tester.tap(find.text(t.vault.remove));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction(t.vault.remove));
    await flush(tester);
    expect(store.load().vaultById('v'), isNull);
    expect(store.load().bindingFor('w'), isNull);
    expect(note.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar new chat confirms leaving an unsaved draft', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text(t.vault.edit));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('vault-note-editor')),
      'Unsaved',
    );
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction(t.vault.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    expect(note.readAsStringSync(), contains('Use Dart.'));
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    await tester.tap(dialogAction(t.vault.discard));
    await flush(tester);
    expect(find.text('Chat destination'), findsOneWidget);
    expect(note.readAsStringSync(), contains('Use Dart.'));
  });

  testWidgets(
    'short narrow editor with keyboard and large text remains scrollable',
    (tester) async {
      await pump(tester, narrow: true);
      await open(tester);
      await tester.tap(find.text(t.vault.edit));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 600);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('vault-note-editor')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('vault-note-editor')),
        'Keyboard edit',
      );
      await tester.ensureVisible(find.text(t.vault.save));
      await tester.tap(find.text(t.vault.save));
      await flush(tester);
      expect(note.readAsStringSync(), 'Keyboard edit');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'another Vault route cannot replace a suspended editor or save target',
    (tester) async {
      await pump(tester);
      await open(tester);
      await tester.tap(find.text(t.vault.edit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('vault-note-editor')),
        'First page draft',
      );
      final router = GoRouter.of(
        tester.element(find.byKey(const ValueKey('vault-page-scaffold'))),
      );
      router.push('/second-vault');
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('vault-entry-Other.md')));
      await flush(tester);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('First page draft'), findsOneWidget);
      await tester.tap(find.text(t.vault.save));
      await flush(tester);
      expect(note.readAsStringSync(), 'First page draft');
      expect(other.readAsStringSync(), 'Keep this note.');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Vault tile above Board shows registered count and opens the reader route',
    (tester) async {
      await pump(tester);
      final router = GoRouter.of(
        tester.element(find.byKey(const ValueKey('vault-page-scaffold'))),
      );
      router.go(AppRoutes.home);
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('navigation-vault'));
      await tester.ensureVisible(tile);
      expect(
        find.descendant(of: tile, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(tile).dy,
        lessThan(tester.getTopLeft(find.text('Board')).dy),
      );
      await tester.tap(tile);
      await flush(tester);
      expect(find.byType(VaultPage), findsOneWidget);
      await open(tester);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      '320px 2x text ${dark ? "dark" : "light"} keeps reader, editor and deletion usable',
      (tester) async {
        await pump(tester, narrow: true, dark: dark);
        await open(tester);
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          find.byKey(const ValueKey('vault-entry-Research/summary.md')),
          findsNothing,
        );
        await tester.tap(find.text(t.vault.edit));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('vault-note-editor')),
          'Large text editing.',
        );
        await tester.tap(find.text(t.vault.save));
        await flush(tester);
        expect(note.readAsStringSync(), 'Large text editing.');
        await tester.tap(find.text(t.vault.delete));
        await tester.pumpAndSettle();
        await tester.tap(dialogAction(t.vault.cancel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(t.vault.backToFiles));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('vault-entry-Research')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
