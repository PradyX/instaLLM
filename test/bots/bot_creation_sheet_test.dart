import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/bots/presentation/create_bot_dialog.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/data/petdex_service.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/bot_portrait_picker.dart';
import 'package:installm/features/profile_images/presentation/profile_image_picker.dart';
import 'package:installm/i18n/strings.g.dart';

class _Petdex extends PetdexService {
  _Petdex(Directory directory) : super(directory: directory, dio: Dio());

  final pets = List.generate(
    8,
    (i) => PetdexPet(
      slug: 'pet-$i',
      name: 'Pet $i',
      spritesheetUrl: 'https://assets.petdex.dev/pets/pet-$i/sprite.webp',
    ),
  );
  final requested = <String>[];
  int catalogRequests = 0;
  bool offline = false;
  Completer<Uint8List>? pending;

  @override
  Future<List<PetdexPet>> catalog({CancelToken? cancelToken}) async {
    catalogRequests++;
    if (offline) throw const SocketException('offline');
    return pets;
  }

  @override
  Future<Uint8List> preview(PetdexPet pet, {CancelToken? cancelToken}) async {
    requested.add(pet.slug);
    if (pending != null) return pending!.future;
    return img.encodePng(img.Image(width: 96, height: 104));
  }

  @override
  Future<File> image(PetdexPet pet, {CancelToken? cancelToken}) async {
    return writeImage(pet);
  }

  File writeImage(PetdexPet pet) {
    final file = cachedFile(pet);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(img.Image(width: 96, height: 104)));
    return file;
  }
}

void main() {
  late Directory directory;
  late _Petdex service;
  BotDraft? draft;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bot_creation_sheet');
    service = _Petdex(directory);
    draft = null;
  });
  tearDown(() async {
    service.close();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [petdexServiceProvider.overrideWith((_) async => service)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    draft = await showCreateBotSheet(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey(key));
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(field('bot-template'));
    await tester.tap(field('bot-template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ordered form has an optional template and editable starter Soul',
    (tester) async {
      await open(tester);
      final order = [
        find.byType(BotPortraitPicker),
        field('bot-name'),
        field('bot-template'),
        field('bot-soul'),
      ].map((finder) => tester.getTopLeft(finder).dy).toList();
      expect(order, orderedEquals([...order]..sort()));
      expect(find.text('Start with'), findsNothing);
      expect(find.text('Template'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      final soul = tester.widget<TextField>(field('bot-soul')).controller!;
      expect(soul.text, t.botCreation.starterSoul);
      expect(soul.text.split('\n'), hasLength(3));
      await tester.enterText(field('bot-name'), 'My companion');
      await tester.ensureVisible(field('bot-soul'));
      await tester.enterText(field('bot-soul'), 'Answer in short sentences.');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(draft!.name, 'My companion');
      expect(draft!.templateId, isNull);
      expect(draft!.soul, 'Answer in short sentences.');
      expect(service.store.load(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('template switching preserves edits for each choice and Name', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field('bot-name'), 'Mine');
    await tester.ensureVisible(field('bot-soul'));
    await tester.enterText(field('bot-soul'), 'My original draft.');
    await choose(tester, 'Planner');
    final soul = tester.widget<TextField>(field('bot-soul')).controller!;
    expect(soul.text, BuiltInBots.byId(BuiltInBots.plannerId)!.soul);
    expect(
      tester.widget<TextField>(field('bot-name')).controller!.text,
      'Mine',
    );
    await tester.ensureVisible(field('bot-soul'));
    await tester.enterText(field('bot-soul'), 'My planning draft.');
    await choose(tester, 'None');
    expect(soul.text, 'My original draft.');
    await choose(tester, 'Planner');
    expect(soul.text, 'My planning draft.');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(draft!.templateId, BuiltInBots.plannerId);
    expect(draft!.soul, 'My planning draft.');
  });

  testWidgets(
    'more portraits slide and search stays in the creation sheet without saving files',
    (tester) async {
      await open(tester);
      expect(service.catalogRequests, 1);
      expect(service.requested, isNot(contains('pet-6')));
      await tester.tap(find.byTooltip('Next portraits'));
      await tester.pumpAndSettle();
      expect(field('bot-portrait-pet-5'), findsOneWidget);
      await tester.tap(find.byTooltip('Next portraits'));
      await tester.pumpAndSettle();
      expect(field('bot-portrait-pet-7'), findsOneWidget);
      await tester.enterText(field('bot-portrait-search'), 'Pet 7');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(service.catalogRequests, 1);
      expect(field('bot-portrait-pet-7'), findsOneWidget);
      expect(find.byType(ProfileImagePicker), findsNothing);
      await tester.tap(field('bot-portrait-pet-7'));
      await tester.pumpAndSettle();
      expect(service.store.load(), isEmpty);
      expect(find.byTooltip('Use default icon'), findsOneWidget);
      // Scrolling the form must not discard the inline search or selection.
      await tester.ensureVisible(field('bot-soul'));
      await tester.ensureVisible(field('bot-portrait-search'));
      expect(field('bot-portrait-pet-7'), findsOneWidget);
      await tester.enterText(field('bot-name'), 'Pet bot');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(draft!.portrait, service.pets[7]);
      expect(service.store.load(), isEmpty);
      expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
    },
  );

  testWidgets('an unavailable catalog still allows offline creation', (
    tester,
  ) async {
    service.offline = true;
    await open(tester);
    expect(find.text(t.botCreation.portraitsOffline), findsOneWidget);
    await tester.enterText(field('bot-name'), 'Offline helper');
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(draft!.portrait, isNull);
    expect(draft!.soul, t.botCreation.starterSoul);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved portraits remain selectable when the web catalog is offline',
    (tester) async {
      final saved = service.pets.last;
      service.store.save({botProfileKey('created'): saved});
      service.writeImage(saved);
      service.offline = true;
      await open(tester);
      await tester.tap(find.text('Saved (1)'));
      await tester.pumpAndSettle();
      expect(field('bot-portrait-pet-7'), findsOneWidget);
      await tester.tap(field('bot-portrait-pet-7'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Use default icon'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft, isNull);
      expect(service.store.load(), {botProfileKey('created'): saved});
      expect(
        directory.listSync(recursive: true).whereType<File>(),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing during image loading ignores a late selection', (
    tester,
  ) async {
    service.pending = Completer<Uint8List>();
    // No settle while the previews are loading indefinitely.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [petdexServiceProvider.overrideWith((_) async => service)],
        child: const MaterialApp(home: Scaffold(body: CreateBotDialog())),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(field('bot-portrait-pet-0'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    service.pending!.complete(img.encodePng(img.Image(width: 96, height: 104)));
    await tester.pumpAndSettle();
    expect(service.store.load(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
