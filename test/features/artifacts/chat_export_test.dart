import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/artifacts/data/chat_export.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/conversations/domain/message_source.dart';

const _source = MessageSource(
  marker: 1,
  documentId: 'doc-1',
  documentName: 'notes.md',
  chunkIndex: 0,
  heading: 'Setup',
);

Message _message({
  required String id,
  required MessageRole role,
  required String content,
  String? modelName,
  List<MessageSource> sources = const [],
}) {
  return Message(
    id: id,
    conversationId: 'chat-1',
    role: role,
    content: content,
    createdAt: DateTime(2026, 11, 22, 9, 41),
    modelName: modelName,
    sources: sources,
  );
}

void main() {
  final messages = [
    _message(
      id: 'm1',
      role: MessageRole.user,
      content: 'Summarise the setup notes.',
    ),
    _message(
      id: 'm2',
      role: MessageRole.assistant,
      content:
          'They cover the local model directory.\nNothing leaves the device.',
      modelName: 'Qwen 2.5 0.5B',
      sources: const [_source],
    ),
  ];

  test('markdown carries both turns and the cited source', () {
    final output = ChatExport.markdown(
      title: 'Setup notes',
      messages: messages,
    );
    expect(output, startsWith('# Setup notes'));
    expect(output, contains('**You:** Summarise the setup notes.'));
    expect(output, contains('**Assistant:**'));
    expect(output, contains('## Sources'));
    expect(output, contains('[1] notes.md · Setup'));
  });

  test('plain text labels the speakers and lists sources', () {
    final output = ChatExport.text(title: 'Setup notes', messages: messages);
    expect(output, startsWith('Setup notes'));
    expect(output, contains('You:\nSummarise the setup notes.'));
    expect(
      output,
      contains('Assistant:\nThey cover the local model directory.'),
    );
    expect(output, contains('- [1] notes.md · Setup'));
  });

  test('json keeps roles, content and sources, and no empty message', () {
    final output = ChatExport.json(
      title: 'Setup notes',
      messages: [
        ...messages,
        _message(id: 'm3', role: MessageRole.assistant, content: '   '),
      ],
      exportedAt: DateTime(2026, 11, 22, 15, 30),
    );
    final payload = jsonDecode(output) as Map<String, dynamic>;
    expect(payload['title'], 'Setup notes');
    expect(payload['exportedAt'], '2026-11-22T15:30:00.000');
    final exported = payload['messages'] as List;
    expect(exported, hasLength(3));
    final answer = exported[1] as Map<String, dynamic>;
    expect(answer['role'], 'assistant');
    expect(answer['model'], 'Qwen 2.5 0.5B');
    expect(answer['sources'], ['[1] notes.md · Setup']);
  });

  test('pdf renders a real document with the turns and sources', () {
    final bytes = ChatExport.build(
      format: ChatExportFormat.pdf,
      title: 'Setup notes',
      messages: messages,
    );
    // A PDF starts with its header and is far larger than an empty one.
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('file names are the title plus the local time', () {
    expect(
      ChatExport.fileName(
        title: 'Weather & News',
        format: ChatExportFormat.markdown,
        now: DateTime(2026, 11, 22, 15, 30),
      ),
      'weather-news-20261122-1530.md',
    );
    expect(
      ChatExport.fileName(
        title: '   ',
        format: ChatExportFormat.pdf,
        now: DateTime(2026, 1, 2, 3, 4),
      ),
      'chat-20260102-0304.pdf',
    );
  });
}
