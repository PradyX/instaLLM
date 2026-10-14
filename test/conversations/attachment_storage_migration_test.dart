import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:installm/core/services/app_storage_service.dart';
import 'package:installm/features/conversations/data/conversation_store.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/conversations/domain/message.dart';

void main() {
  late Directory base;
  late Directory documents;
  late Directory conversations;
  late AppStorageService storage;
  late ConversationStore store;
  setUp(() {
    base = Directory.systemTemp.createTempSync('installm-path-migration-');
    documents = Directory(p.join(base.path, 'Documents'))..createSync();
    conversations = Directory(p.join(base.path, 'conversations'))..createSync();
    storage = AppStorageService(documentsDirectory: documents, mobile: false);
    store = ConversationStore(
      rootDirectory: conversations,
      appStorage: storage,
    );
  });
  tearDown(() => base.deleteSync(recursive: true));

  File attachment(String folder, String name) {
    final file = File(p.join(documents.path, 'attachments', folder, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('photo-$folder');
    return file;
  }

  Future<File> history(String path, {int version = 2}) async {
    final file = File(p.join(conversations.path, 'c1.json'));
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': version,
        'conversation': Conversation.create(
          id: 'c1',
          title: 'Keep me',
        ).toJson(),
        'unknown': {'keep': true},
        'messages': [
          {
            ...Message.create(
              conversationId: 'c1',
              role: MessageRole.user,
              content: 'Original words',
            ).toJson(),
            'imagePath': path,
            'unknownMessageField': 'keep',
            'attachments': [
              {
                'id': 'a1',
                'type': 'image',
                'path': path,
                'unknownAttachmentField': 42,
              },
              {'id': 'partial', 'path': 42},
            ],
          },
          {'partial': 'preserve'},
          'malformed-but-preserved',
        ],
      }),
    );
    return file;
  }

  test(
    'rewrites only managed paths, preserving partial and unknown JSON',
    () async {
      final photo = attachment('c1', 'same.jpg');
      attachment('c2', 'same.jpg');
      final file = await history(photo.path);
      final original = await file.readAsString();
      await store.loadMessages('c1');
      final payload = jsonDecode(await file.readAsString()) as Map;
      expect(payload['schemaVersion'], 3);
      expect(payload['unknown'], {'keep': true});
      final raw = (payload['messages'] as List).first as Map;
      final expected = p.join(
        documents.path,
        'InstaLLM/attachments/c1/same.jpg',
      );
      expect(raw['imagePath'], expected);
      expect((raw['attachments'] as List).first['path'], expected);
      expect((raw['attachments'] as List).first['unknownAttachmentField'], 42);
      expect(raw['unknownMessageField'], 'keep');
      expect((raw['attachments'] as List).last, {'id': 'partial', 'path': 42});
      expect((payload['messages'] as List).last, 'malformed-but-preserved');
      expect(
        await File('${file.path}.pre-storage-v3').readAsString(),
        original,
      );
      final after = await file.readAsString();
      await store.loadMessages('c1');
      expect(await file.readAsString(), after);
    },
  );

  test(
    'legacy valid history remains usable after move and fresh store load',
    () async {
      final photo = attachment('c1', 'image.jpg');
      final file = await history(photo.path);
      final payload = jsonDecode(await file.readAsString()) as Map;
      final raw = (payload['messages'] as List).first as Map;
      (raw['attachments'] as List).removeLast();
      payload['messages'] = [raw];
      await file.writeAsString(jsonEncode(payload));
      final before = raw['createdAt'];
      final loaded = await store.loadMessages('c1');
      expect(loaded.single.content, 'Original words');
      expect(await File(loaded.single.imagePath!).readAsString(), 'photo-c1');
      final restarted = ConversationStore(
        rootDirectory: conversations,
        appStorage: storage,
      );
      expect(
        (await restarted.loadMessages('c1')).single.createdAt.toIso8601String(),
        before,
      );
      expect((await restarted.loadConversation('c1'))?.title, 'Keep me');
    },
  );

  test('external and unsupported paths/payloads stay unchanged', () async {
    attachment('c1', 'same.jpg');
    final external = p.join(base.path, 'external/same.jpg');
    final file = await history(external);
    await store.loadMessages('c1');
    final payload = jsonDecode(await file.readAsString()) as Map;
    expect((payload['messages'] as List).first['imagePath'], external);
    await history(external, version: 99);
    final original = await file.readAsString();
    expect(await store.loadMessages('c1'), isEmpty);
    expect(await file.readAsString(), original);
  });

  test(
    'failed original preservation leaves source JSON untouched and retries',
    () async {
      final photo = attachment('c1', 'image.jpg');
      final file = await history(photo.path);
      final original = await file.readAsString();
      final backupBlocker = Directory('${file.path}.pre-storage-v3')
        ..createSync();
      await store.loadMessages('c1');
      expect(await file.readAsString(), original);
      await backupBlocker.delete();
      await store.loadMessages('c1');
      expect(
        (jsonDecode(await file.readAsString()) as Map)['schemaVersion'],
        3,
      );
      expect(
        await File('${file.path}.pre-storage-v3').readAsString(),
        original,
      );
    },
  );
}
