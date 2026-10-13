import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:installm/core/widgets/default_bot_avatar.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';
import 'package:installm/features/bots/presentation/create_bot_dialog.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/data/petdex_service.dart';
import 'package:installm/features/profile_images/domain/petdex_pet.dart';
import 'package:installm/features/profile_images/presentation/profile_avatar.dart';
import 'package:installm/features/profile_images/presentation/profile_image_picker.dart';

const _boba = PetdexPet(
  slug: 'boba',
  name: 'Boba',
  creator: 'railly',
  spritesheetUrl: 'https://assets.petdex.dev/curated/boba/sprite.webp',
);
const _cat = PetdexPet(
  slug: 'cat',
  name: 'Cat',
  spritesheetUrl: 'https://assets.petdex.dev/pets/cat/sprite.webp',
);

class _FakePetdex extends PetdexService {
  _FakePetdex(Directory directory) : super(directory: directory, dio: Dio());
  var catalogRequests = 0;
  final requestedImages = <String>[];
  var failImages = false;

  @override
  Future<List<PetdexPet>> catalog({CancelToken? cancelToken}) async {
    catalogRequests++;
    return [_boba, _cat];
  }

  @override
  Future<File> image(PetdexPet pet, {CancelToken? cancelToken}) async {
    requestedImages.add(pet.slug);
    if (failImages) throw const SocketException('offline');
    final file = cachedFile(pet);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(img.Image(width: 96, height: 104)));
    return file;
  }
}

void main() {
  late Directory directory;
  late _FakePetdex service;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('petdex_widget_test');
    service = _FakePetdex(directory);
  });
  tearDown(() async {
    service.close();
    await directory.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [
            petdexServiceProvider.overrideWith((ref) async => service),
            botStoreProvider.overrideWith(
              (ref) async => BotStore(File('${directory.path}/bots.json')),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: child),
          ),
        ),
      );

  testWidgets(
    'new bot portrait is a draft; create returns it and cancel saves nothing',
    (tester) async {
      BotDraft? draft;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              draft = await showDialog<BotDraft>(
                context: context,
                builder: (_) => const CreateBotDialog(),
              );
            },
            child: const Text('New bot'),
          ),
        ),
      );
      await tester.tap(find.text('New bot'));
      await tester.pumpAndSettle();
      expect(service.catalogRequests, 0);
      await tester.enterText(find.byType(TextField), 'My bot');
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Boba');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      );
      await tester.pumpAndSettle();
      expect(service.store.load(), isEmpty);
      expect(find.byType(PetdexAvatar), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft, isNull);
      expect(service.store.load(), isEmpty);

      await tester.tap(find.text('New bot'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Portrait bot');
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Boba');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(draft?.name, 'Portrait bot');
      expect(draft?.portrait, _boba);
      expect(service.store.load(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening picker loads no gallery; search loads only matches, selection persists and can be removed',
    (tester) async {
      final key = botProfileKey(BuiltInBots.coderId);
      await pump(tester, ProfileImageButton(profileKey: key));
      await tester.pumpAndSettle();
      expect(find.byType(DefaultBotAvatar), findsOneWidget);
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(service.catalogRequests, 0);
      expect(service.requestedImages, isEmpty);

      await tester.enterText(find.byType(TextField), 'Boba');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(service.catalogRequests, 1);
      expect(service.requestedImages, ['boba']);
      expect(find.text('Cat'), findsNothing);
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfileImagePicker), findsNothing);
      expect(service.store.load()[key], _boba);
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use default icon'));
      await tester.pumpAndSettle();
      expect(service.store.load(), isEmpty);
      expect(find.byType(DefaultBotAvatar), findsOneWidget);
    },
  );

  testWidgets(
    'failed image selection keeps default and shows actionable error',
    (tester) async {
      service.failImages = true;
      await pump(
        tester,
        const ProfileImageButton(
          profileKey: 'room:dev',
          fallback: Icon(Icons.forum_outlined),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Boba');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not load this image. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(service.store.load(), isEmpty);
      service.failImages = false;
      await tester.tap(
        find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      );
      await tester.pumpAndSettle();
      expect(service.store.load()['room:dev'], _boba);
    },
  );

  testWidgets('failed selected image uses fallback without blocking chat', (
    tester,
  ) async {
    service.failImages = true;
    service.store.save({'bot:b': _boba});
    await pump(tester, const ProfileAvatar(profileKey: 'bot:b'));
    await tester.pumpAndSettle();
    expect(find.byType(DefaultBotAvatar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'room header uses a group room selection and a direct room follows its bot',
    (tester) async {
      service.store.save({
        'room:dev': _cat,
        botProfileKey(BuiltInBots.coderId): _boba,
      });
      final group = GroupChat.create(
        id: 'dev',
        workspaceId: 'ws',
        name: 'Dev',
        memberBotIds: [BuiltInBots.coderId],
      );
      final direct = GroupChat.create(
        id: 'direct',
        workspaceId: 'ws',
        name: 'Coder',
        directBotId: BuiltInBots.coderId,
        memberBotIds: [BuiltInBots.coderId],
      );
      await pump(
        tester,
        Column(
          children: [
            RoomHeaderTitle(room: group),
            RoomHeaderTitle(room: direct),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<PetdexAvatar>(find.byType(PetdexAvatar))
            .map((avatar) => avatar.pet.slug),
        ['cat', 'boba'],
      );
      expect(find.text('Dev'), findsOneWidget);
      expect(find.text('Coder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('picker fits a narrow window and large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      const ProfileImageButton(
        profileKey: 'room:dev',
        fallback: Icon(Icons.forum_outlined),
      ),
      scale: 2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Boba');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('Boba')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
