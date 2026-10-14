import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';

class _FailingStore extends BotStore {
  _FailingStore(super.file);
  bool failWrites = false;
  @override
  bool save(BotsSnapshot snapshot) => !failWrites && super.save(snapshot);
}

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bot_registry');
    file = File('${directory.path}/bots.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  ProviderContainer open({BotStore? store}) {
    final container = ProviderContainer(
      overrides: [
        botStoreProvider.overrideWith((_) async => store ?? BotStore(file)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<BotsNotifier> loaded(ProviderContainer container) async {
    final notifier = container.read(botsProvider.notifier);
    for (var i = 0; i < 100 && !container.read(botsProvider).isReady; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(container.read(botsProvider).isReady, isTrue);
    return notifier;
  }

  test(
    'a fresh install has no active bots and does not create a file',
    () async {
      final container = open();
      await loaded(container);
      expect(container.read(botsProvider).bots, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(BuiltInBots.all(), hasLength(4));
    },
  );

  test(
    'template creation is explicit, uses a fresh ID and is editable',
    () async {
      final container = open();
      final notifier = await loaded(container);
      final bot = await notifier.createBot(
        'My planner',
        templateId: BuiltInBots.plannerId,
      );
      expect(bot, isNotNull);
      expect(bot!.id, isNot(BuiltInBots.plannerId));
      expect(bot.isBuiltIn, isFalse);
      expect(bot.soul, BuiltInBots.byId(BuiltInBots.plannerId)!.soul);
      expect(container.read(botsProvider).bots, hasLength(1));
      expect(
        await notifier.updateBot(
          bot.copyWith(name: 'Changed', soul: 'My rules.'),
        ),
        isTrue,
      );
      final restored = BotStore(file).load().allBots.single;
      expect(restored.name, 'Changed');
      expect(restored.soul, 'My rules.');
      expect(restored.id, bot.id);
    },
  );

  test('blank creation has no template instructions or skills', () async {
    final container = open();
    final notifier = await loaded(container);
    final bot = await notifier.createBot('Mine');
    expect(bot!.soul, isEmpty);
    expect(bot.skillIds, isEmpty);
    expect(await notifier.createBot('Bad', templateId: 'unknown'), isNull);
    expect(container.read(botsProvider).bots, hasLength(1));
  });

  test(
    'creation persists edited Soul and respects an explicitly cleared Soul',
    () async {
      final notifier = await loaded(open());
      final edited = await notifier.createBot(
        'My planner',
        templateId: BuiltInBots.plannerId,
        soul: 'Use my own planning rules.',
      );
      final cleared = await notifier.createBot(
        'No instructions',
        templateId: BuiltInBots.coderId,
        soul: '',
      );
      final restored = BotStore(file).load();
      expect(
        restored.allBots.singleWhere((b) => b.id == edited!.id).soul,
        'Use my own planning rules.',
      );
      expect(
        restored.allBots.singleWhere((b) => b.id == cleared!.id).soul,
        isEmpty,
      );
    },
  );

  test('deleting the last bot survives a restart without reseeding', () async {
    final notifier = await loaded(open());
    final bot = await notifier.duplicateTemplate(BuiltInBots.coderId);
    expect(await notifier.removeBot(bot!.id), isTrue);
    final restarted = open();
    await loaded(restarted);
    expect(restarted.read(botsProvider).bots, isEmpty);
    expect(jsonDecode(file.readAsStringSync())['version'], 2);
    expect(jsonDecode(file.readAsStringSync())['bots'], isEmpty);
  });

  test(
    'v1 migration preserves custom data and the original partial payload',
    () {
      final bot = Bot.create(
        name: 'Mine',
        soul: 'Private rules.',
        modelId: 'local',
        workspaceIds: ['ws'],
      );
      final raw = jsonEncode({
        'version': 1,
        'bots': [
          bot.toJson(),
          {'id': 9, 'name': 'bad'},
          null,
          BuiltInBots.all().first.toJson(),
        ],
        'unknown': 'retained in backup',
      });
      file.writeAsStringSync(raw);
      final store = BotStore(file);
      final snapshot = store.load();
      expect(snapshot.allBots.map((b) => b.id), [bot.id]);
      expect(snapshot.allBots.single.soul, bot.soul);
      expect(file.readAsStringSync(), raw);
      expect(store.save(snapshot), isTrue);
      final backup = directory.listSync().whereType<File>().singleWhere(
        (f) => f.path.contains('.v1-'),
      );
      expect(backup.readAsStringSync(), raw);
      expect(BotStore(file).load().allBots.single.toJson(), bot.toJson());
      expect(jsonDecode(file.readAsStringSync())['version'], 2);
    },
  );

  test('partial v2 and duplicate records do not recreate templates', () {
    file.writeAsStringSync(
      jsonEncode({
        'version': 2,
        'bots': [
          null,
          {'id': 4},
          {'id': 'b', 'name': 'One'},
          {'id': 'b', 'name': 'Two'},
        ],
      }),
    );
    final raw = file.readAsStringSync();
    final store = BotStore(file);
    final snapshot = store.load();
    final bots = snapshot.allBots;
    expect(bots, hasLength(1));
    expect(bots.single.name, 'One');
    expect(bots.single.isBuiltIn, isFalse);
    expect(store.save(snapshot), isTrue);
    final backup = directory.listSync().whereType<File>().singleWhere(
      (file) => file.path.contains('.partial-'),
    );
    expect(backup.readAsStringSync(), raw);
  });

  test('corrupt JSON is backed up byte-for-byte before creation', () async {
    const raw = '{broken private data';
    file.writeAsStringSync(raw);
    final notifier = await loaded(open());
    expect(await notifier.createBot('New'), isNotNull);
    final backup = directory.listSync().whereType<File>().singleWhere(
      (f) => f.path.contains('.corrupt-'),
    );
    expect(backup.readAsStringSync(), raw);
    expect(BotStore(file).load().allBots.single.name, 'New');
  });

  test('a newer registry is read-only and left byte-for-byte intact', () async {
    const raw = '{"version":99,"bots":[{"id":"future","name":"Future"}]}';
    file.writeAsStringSync(raw);
    final container = open();
    final notifier = await loaded(container);
    expect(container.read(botsProvider).isReadOnly, isTrue);
    expect(await notifier.createBot('No'), isNull);
    expect(file.readAsStringSync(), raw);
  });

  test(
    'failed create, edit and delete never change the visible registry',
    () async {
      final store = _FailingStore(file);
      final container = open(store: store);
      final notifier = await loaded(container);
      final bot = (await notifier.createBot('Keep'))!;
      final raw = file.readAsStringSync();
      store.failWrites = true;
      expect(await notifier.createBot('Lost'), isNull);
      expect(await notifier.updateBot(bot.copyWith(name: 'Lost')), isFalse);
      expect(await notifier.removeBot(bot.id), isFalse);
      expect(container.read(botsProvider).bots.single.name, 'Keep');
      expect(file.readAsStringSync(), raw);
      expect(container.read(botsProvider).errorMessage, isNotNull);
    },
  );

  test(
    'concurrent creations wait for initial load and preserve both bots',
    () async {
      final notifier = open().read(botsProvider.notifier);
      final bots = await Future.wait([
        notifier.createBot('One'),
        notifier.createBot('Two'),
      ]);
      expect(bots.every((bot) => bot != null), isTrue);
      expect(BotStore(file).load().allBots.map((bot) => bot.name), [
        'One',
        'Two',
      ]);
    },
  );
}
