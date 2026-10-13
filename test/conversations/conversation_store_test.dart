import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/domain/message.dart';

void main() {
  late Directory tempDir;
  late ConversationStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('installm_store_test');
    store = ConversationStore(rootDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Conversation conversation({String id = 'c-1', String title = 'Chat'}) {
    return Conversation.create(id: id, title: title);
  }

  Message message(String conversationId, String content) {
    return Message.create(
      conversationId: conversationId,
      role: MessageRole.user,
      content: content,
    );
  }

  File indexFile() => File(p.join(tempDir.path, 'index.json'));

  test('starts empty and writes a valid index after loading', () async {
    expect(await store.loadSummaries(), isEmpty);
    expect(await indexFile().exists(), isTrue);
    final decoded = jsonDecode(await indexFile().readAsString()) as Map;
    expect(decoded['schemaVersion'], conversationStoreSchemaVersion);
  });

  test('creates, loads and updates conversations', () async {
    await store.createConversation(conversation());
    final summaries = await store.loadSummaries();
    expect(summaries, hasLength(1));

    final loaded = await store.loadConversation('c-1');
    expect(loaded?.title, 'Chat');

    await store.updateConversation(loaded!.copyWith(title: 'Renamed'));
    expect((await store.loadConversation('c-1'))?.title, 'Renamed');
  });

  test('saves messages and updates the summary preview', () async {
    await store.createConversation(conversation());
    await store.saveMessages(conversation(), [message('c-1', 'Hello there')]);

    final messages = await store.loadMessages('c-1');
    expect(messages, hasLength(1));
    expect(messages.single.content, 'Hello there');

    final summary = (await store.loadSummaries()).single;
    expect(summary.messageCount, 1);
    expect(summary.lastMessagePreview, 'Hello there');
    expect(summary.lastMessageAt, isNotNull);
  });

  test('deletes a conversation file and index entry', () async {
    await store.createConversation(conversation());
    await store.deleteConversation('c-1');
    expect(await store.loadSummaries(), isEmpty);
    expect(await File(p.join(tempDir.path, 'c-1.json')).exists(), isFalse);
  });

  test('rebuilds a corrupt index from conversation files', () async {
    await store.createConversation(conversation());
    await indexFile().writeAsString('not json');

    final summaries = await store.loadSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.conversation.id, 'c-1');

    final index = jsonDecode(await indexFile().readAsString()) as Map;
    expect(index['schemaVersion'], conversationStoreSchemaVersion);
  });

  test('skips corrupt conversation files without deleting them', () async {
    await store.createConversation(conversation());
    final corrupt = File(p.join(tempDir.path, 'c-broken.json'));
    await corrupt.writeAsString('{ not valid json');

    final summaries = await store.loadSummaries();
    expect(summaries, hasLength(1));
    expect(await corrupt.exists(), isTrue);
  });

  test('leaves an index with an unsupported schema untouched', () async {
    const futureIndex = '{"schemaVersion": 99, "conversations": []}';
    await indexFile().writeAsString(futureIndex);

    expect(await store.loadSummaries(), isEmpty);
    expect(await indexFile().readAsString(), futureIndex);
  });

  test('round-trips metadata flags', () async {
    expect(await store.readMetaFlag('migrated'), isFalse);
    await store.writeMetaFlag('migrated', true);
    expect(await store.readMetaFlag('migrated'), isTrue);
    final index = jsonDecode(await indexFile().readAsString()) as Map;
    expect((index['meta'] as Map)['migrated'], isTrue);
  });

  test('leaves no temporary files behind after writes', () async {
    await store.createConversation(conversation());
    await store.saveMessages(conversation(), [message('c-1', 'Hello')]);
    final leftovers = tempDir.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.tmp'),
    );
    expect(leftovers, isEmpty);
  });

  group('schema migration', () {
    File conversationFile(String id) => File(p.join(tempDir.path, '$id.json'));

    /// Writes a conversation file exactly as schema version [version] wrote
    /// it, including the document scope that version 2 removed.
    Future<File> writeVersionedConversation({
      required String id,
      required int version,
      String title = 'Legacy chat',
      Object? documentCollectionId = 'col-work',
      Object? documentsEnabled = false,
    }) async {
      final file = conversationFile(id);
      await file.writeAsString(
        jsonEncode({
          'schemaVersion': version,
          'conversationId': id,
          'conversation': {
            'id': id,
            'title': title,
            'createdAt': DateTime.utc(2026).toIso8601String(),
            'updatedAt': DateTime.utc(2026).toIso8601String(),
            'documentCollectionId': documentCollectionId,
            'documentsEnabled': documentsEnabled,
          },
          'messages': [
            {
              'id': 'm-1',
              'conversationId': id,
              'role': 'user',
              'content': 'Hello from before the change',
              'createdAt': DateTime.utc(2026).toIso8601String(),
            },
          ],
        }),
      );
      return file;
    }

    test('migrates a version 1 conversation file in place', () async {
      final file = await writeVersionedConversation(id: 'c-legacy', version: 1);

      final loaded = await store.loadConversation('c-legacy');
      expect(loaded?.title, 'Legacy chat');

      final migrated = jsonDecode(await file.readAsString()) as Map;
      expect(migrated['schemaVersion'], conversationStoreSchemaVersion);

      final stored = migrated['conversation'] as Map;
      expect(stored.containsKey('documentCollectionId'), isFalse);
      expect(stored.containsKey('documentsEnabled'), isFalse);

      // Nothing else moved: the chat and its messages are intact.
      expect(stored['title'], 'Legacy chat');
      final messages = migrated['messages'] as List;
      expect(messages, hasLength(1));
      expect(
        (messages.single as Map)['content'],
        'Hello from before the change',
      );
    });

    test('messages of a migrated chat stay readable', () async {
      await writeVersionedConversation(id: 'c-legacy', version: 1);

      final messages = await store.loadMessages('c-legacy');
      expect(messages, hasLength(1));
      expect(messages.single.content, 'Hello from before the change');
    });

    test(
      'a version 1 file with malformed scope values still migrates',
      () async {
        final file = await writeVersionedConversation(
          id: 'c-bad',
          version: 1,
          documentCollectionId: 42,
          documentsEnabled: 'yes',
        );

        expect((await store.loadConversation('c-bad'))?.title, 'Legacy chat');

        final migrated = jsonDecode(await file.readAsString()) as Map;
        expect(migrated['schemaVersion'], conversationStoreSchemaVersion);
      },
    );

    test('upgrades a version 1 index on the first read', () async {
      await store.createConversation(conversation());
      final index = jsonDecode(await indexFile().readAsString()) as Map;
      index['schemaVersion'] = 1;
      index['conversations'] = [
        for (final raw in index['conversations'] as List)
          {
            ...Map<String, dynamic>.from(raw as Map),
            'documentCollectionId': 'col-work',
            'documentsEnabled': false,
          },
      ];
      await indexFile().writeAsString(jsonEncode(index));

      final summaries = await store.loadSummaries();
      expect(summaries, hasLength(1));

      final rewritten = jsonDecode(await indexFile().readAsString()) as Map;
      expect(rewritten['schemaVersion'], conversationStoreSchemaVersion);
      final entry = (rewritten['conversations'] as List).single as Map;
      expect(entry.containsKey('documentCollectionId'), isFalse);
      expect(entry.containsKey('documentsEnabled'), isFalse);
    });

    test('leaves a version 1 file alone when it cannot be read', () async {
      final file = conversationFile('c-broken');
      await file.writeAsString('not json at all');

      expect(await store.loadConversation('c-broken'), isNull);
      expect(await file.readAsString(), 'not json at all');
    });

    test('leaves a conversation file from a newer schema untouched', () async {
      final future = await writeVersionedConversation(
        id: 'c-future',
        version: conversationStoreSchemaVersion + 1,
      );
      final before = await future.readAsString();

      expect(await store.loadConversation('c-future'), isNull);
      expect(await future.readAsString(), before);
    });
  });
}
