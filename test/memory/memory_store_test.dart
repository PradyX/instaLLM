import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';

class _BackupFailingFile implements File {
  _BackupFailingFile(this.original);
  final File original;
  @override
  String get path => original.path;
  @override
  Directory get parent => original.parent;
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      original.readAsStringSync(encoding: encoding);
  @override
  File copySync(String newPath) => throw const FileSystemException('No space');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MemoryFact fact({
  String id = 'f1',
  MemoryScope scope = MemoryScope.workspace,
  String? ownerId = 'ws1',
  bool globalOptIn = false,
  MemorySource source = MemorySource.userStated,
}) => MemoryFact(
  id: id,
  scope: scope,
  ownerId: ownerId,
  text: 'Use Dart.',
  source: source,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026, 10),
  expiresAt: DateTime.utc(2027),
  globalOptIn: globalOptIn,
);

void main() {
  late Directory root;
  late File file;
  late MemoryStore store;
  setUp(() {
    root = Directory.systemTemp.createTempSync('installm_memory_store_');
    file = File('${root.path}/memory/facts.json');
    store = MemoryStore(file);
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(Object payload) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(payload));
  }

  List<File> backups() => file.parent
      .listSync()
      .whereType<File>()
      .where((entry) => entry.path.contains('.preserved-'))
      .toList();

  test('fresh install is empty and creates no file on read', () {
    expect(store.load(), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('save/load preserves scopes, source, dates and consent', () {
    final facts = [
      fact(),
      fact(
        id: 'f2',
        scope: MemoryScope.global,
        ownerId: null,
        globalOptIn: true,
        source: MemorySource.inferred,
      ),
      fact(id: 'f3', scope: MemoryScope.conversation, ownerId: 'c1'),
    ];
    expect(store.save(facts), isTrue);
    expect(
      MemoryStore(file).load().map((entry) => entry.toJson()),
      facts.map((entry) => entry.toJson()),
    );
    expect(jsonDecode(file.readAsStringSync())['version'], 1);
    expect(file.parent.listSync(), hasLength(1));
  });

  test('unversioned migration preserves payload before a v1 write', () {
    write({
      'facts': [fact().toJson()],
      'legacyField': 'retain this',
    });
    final original = file.readAsStringSync();
    final loaded = store.load();
    expect(loaded.single.id, 'f1');
    expect(file.readAsStringSync(), original);
    expect(store.save(loaded), isTrue);
    expect(backups().single.readAsStringSync(), original);
    expect(store.save(loaded), isTrue);
    expect(backups(), hasLength(1));
  });

  test('partial and duplicate entries are preserved before rewrite', () {
    write({
      'version': 1,
      'facts': [
        fact().toJson(),
        42,
        {'text': 'incomplete'},
        fact().toJson(),
      ],
    });
    final original = file.readAsStringSync();
    final loaded = store.load();
    expect(loaded, hasLength(1));
    expect(store.save(loaded), isTrue);
    expect(backups().single.readAsStringSync(), original);
  });

  test('failed preservation copy refuses to overwrite damaged user data', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{damaged but precious');
    final failing = MemoryStore(_BackupFailingFile(file));
    expect(failing.load(), isEmpty);
    expect(failing.save([fact()]), isFalse);
    expect(file.readAsStringSync(), '{damaged but precious');
    expect(file.parent.listSync(), hasLength(1));
  });

  for (final raw in ['{broken', '[]', '{"version":1,"facts":{}}']) {
    test('preserves unreadable payload $raw before recovery', () {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(raw);
      expect(store.load(), isEmpty);
      expect(store.save([fact()]), isTrue);
      expect(backups().single.readAsStringSync(), raw);
      expect(MemoryStore(file).load().single.id, 'f1');
    });
  }

  for (final version in [99, '2', -1]) {
    test('refuses unsupported version $version even before load', () {
      write({
        'version': version,
        'facts': [fact().toJson()],
      });
      final original = file.readAsStringSync();
      expect(store.save([]), isFalse);
      expect(store.isReadOnly, isTrue);
      expect(file.readAsStringSync(), original);
      expect(backups(), isEmpty);
    });
  }

  test('failed write keeps the previously saved file', () {
    expect(store.save([fact()]), isTrue);
    final original = file.readAsStringSync();
    expect(store.save([fact(), fact()]), isFalse);
    expect(file.readAsStringSync(), original);
  });

  test(
    'unavailable directory returns failure without deleting its contents',
    () {
      final blocked = File('${root.path}/blocked')..writeAsStringSync('keep');
      expect(
        MemoryStore(File('${blocked.path}/facts.json')).save([fact()]),
        isFalse,
      );
      expect(blocked.readAsStringSync(), 'keep');
    },
  );

  test(
    'global consent defaults off and invalid scope never broadens recall',
    () {
      final global = fact(scope: MemoryScope.global, ownerId: null).toJson()
        ..remove('globalOptIn');
      expect(MemoryFact.fromJson(global)?.globalOptIn, isFalse);
      for (final invalid in [
        {...fact().toJson(), 'scope': 'futureScope'},
        {...fact().toJson(), 'source': 'futureSource'},
        {...fact().toJson(), 'ownerId': null},
        {...fact().toJson(), 'expiresAt': 'invalid'},
        {...fact().toJson(), 'updatedAt': '2025-01-01'},
        {...global, 'globalOptIn': 'true'},
        {...fact().toJson(), 'text': ' '},
      ]) {
        expect(MemoryFact.fromJson(invalid), isNull);
      }
    },
  );
}
