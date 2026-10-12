import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/features/group_chat/application/group_chat_controller.dart';
import 'package:pocket_llm/features/group_chat/domain/group_chat.dart';

/// The room the chat page is showing, or null for the conversation.
///
/// The app has one chat page: the same header, transcript and composer serve a
/// conversation, a bot's 1:1 chat and a group room. This provider is the whole
/// of that difference — a room id here means the page draws that room, and
/// nothing here touches which conversation is loaded, so going back to a chat
/// is instant and nothing is torn down.
final activeRoomIdProvider = StateProvider<String?>((ref) => null);

/// Shows [roomId] on the chat page. Every list that can open a room goes
/// through this, so "a room is open" has exactly one meaning.
void showRoom(WidgetRef ref, String roomId) {
  ref.read(activeRoomIdProvider.notifier).state = roomId;
}

/// Returns the chat page to the conversation, which stays exactly as it was.
void showConversation(WidgetRef ref) {
  ref.read(activeRoomIdProvider.notifier).state = null;
}

/// The open room itself, or null when the page is showing the conversation.
///
/// A room deleted while it is open reads as null too, so the page falls back to
/// the conversation instead of drawing a room that no longer exists.
final activeRoomProvider = Provider<GroupChat?>((ref) {
  final roomId = ref.watch(activeRoomIdProvider);
  if (roomId == null) return null;
  for (final chat in ref.watch(groupChatsProvider).snapshot.chats) {
    if (chat.id == roomId) return chat;
  }
  return null;
});
