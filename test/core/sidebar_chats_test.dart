import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/core/navigation/app_shell.dart';
import 'package:pocket_llm/features/conversations/domain/conversation.dart';
import 'package:pocket_llm/features/conversations/presentation/conversation_controller.dart';

/// A chat for these tests; [id] is also the title, so assertions read plainly.
/// [minutesAgo] is how long since it last changed.
ConversationSummary _chat(
  String id, {
  required int minutesAgo,
  bool pinned = false,
}) {
  final at = DateTime.utc(
    2026,
    10,
    12,
    12,
  ).subtract(Duration(minutes: minutesAgo));
  return ConversationSummary(
    conversation: Conversation(
      id: id,
      title: id,
      createdAt: at,
      updatedAt: at,
      isPinned: pinned,
    ),
    messageCount: 0,
    lastMessagePreview: '',
    lastMessageAt: null,
  );
}

/// The ids the sidebar would list, in order.
List<String> _listed(ConversationListState state) => [
  for (final summary in sidebarChatSummaries(state.visibleSummaries))
    summary.conversation.id,
];

void main() {
  test('lists pinned chats, then the five most recent of the rest', () {
    final state = ConversationListState(
      summaries: [
        _chat('old-pinned', minutesAgo: 600, pinned: true),
        _chat('new-pinned', minutesAgo: 5, pinned: true),
        for (var age = 1; age <= 8; age++)
          _chat('recent-$age', minutesAgo: age),
      ],
    );

    expect(_listed(state), [
      'new-pinned',
      'old-pinned',
      'recent-1',
      'recent-2',
      'recent-3',
      'recent-4',
      'recent-5',
    ]);
  });

  test('a pinned chat does not take one of the five recent slots', () {
    final state = ConversationListState(
      summaries: [
        _chat('pinned', minutesAgo: 0, pinned: true),
        for (var age = 1; age <= 6; age++)
          _chat('recent-$age', minutesAgo: age),
      ],
    );

    // The pinned chat is listed in addition to the five, so a pinned chat
    // never pushes a recent one out.
    expect(_listed(state), [
      'pinned',
      'recent-1',
      'recent-2',
      'recent-3',
      'recent-4',
      'recent-5',
    ]);
  });

  test('every pinned chat is listed, however many there are', () {
    final state = ConversationListState(
      summaries: [
        for (var pinned = 1; pinned <= 7; pinned++)
          _chat('pinned-$pinned', minutesAgo: pinned, pinned: true),
        _chat('recent', minutesAgo: 100),
      ],
    );

    expect(_listed(state), [
      for (var pinned = 1; pinned <= 7; pinned++) 'pinned-$pinned',
      'recent',
    ]);
  });

  test('fewer chats than the limit are all listed', () {
    final state = ConversationListState(
      summaries: [
        _chat('one', minutesAgo: 1),
        _chat('two', minutesAgo: 2),
        _chat('three', minutesAgo: 3),
      ],
    );

    expect(_listed(state), ['one', 'two', 'three']);
  });

  test('searching narrows what the sidebar lists, and the cap still holds', () {
    final state = ConversationListState(
      summaries: [
        _chat('budget', minutesAgo: 1),
        for (var chats = 1; chats <= 7; chats++)
          _chat('other-$chats', minutesAgo: chats + 1),
      ],
      searchQuery: 'budget',
    );

    expect(_listed(state), ['budget']);

    final cleared = state.copyWith(searchQuery: '');
    expect(_listed(cleared).length, sidebarRecentChatCount);
    expect(_listed(cleared).first, 'budget');
  });
}
