import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';
import 'package:installm/features/home/domain/reply_notice.dart';

final replyNoticeServiceProvider = Provider<ReplyNoticeService>((ref) {
  final service = ReplyNoticeService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Tells the user a reply finished while they were not looking at it
/// (Road Map 5 Phase 5.6).
///
/// The notice goes through the same `flutter_local_notifications` plugin the
/// reminders and agent runs already use — no service, no alarm, no new
/// permission — and its payload opens the conversation the answer belongs to.
/// What it carries is [ReplyNotice.excerpt], so the shade shows at most a
/// sentence of the answer and never the question.
class ReplyNoticeService with WidgetsBindingObserver {
  ReplyNoticeService(this._ref);

  final Ref _ref;

  AppLifecycleState? _lifecycle;
  StreamSubscription<String>? _taps;
  bool _started = false;

  /// Message ids already announced, newest last: one notice per reply even if
  /// a second call site reaches the same finished message.
  final List<String> _announced = <String>[];

  static const int _announcedMemory = 24;

  bool get isStarted => _started;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _taps = LocalNotificationService.taps.listen(_open);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  /// True while the app is in front of the user.
  ///
  /// A null answer is the platform saying nothing yet (a test, or a first
  /// frame); it is treated as foreground so a notice is never posted blind.
  bool get isAppInForeground =>
      _lifecycle == null || _lifecycle == AppLifecycleState.resumed;

  /// Posts the notice for a finished reply, if the user is not looking at it.
  Future<void> announceReply({
    required String conversationId,
    required String messageId,
    required String reply,
    required bool fromScheduledJob,
  }) async {
    if (conversationId.isEmpty || messageId.isEmpty) return;
    if (_announced.contains(messageId)) return;
    if (!ReplyNotice.shouldAnnounce(
      lifecycle: _lifecycle,
      conversationVisible:
          isAppInForeground &&
          _ref.read(conversationControllerProvider).activeConversationId ==
              conversationId,
      fromScheduledJob: fromScheduledJob,
    )) {
      return;
    }

    final body = ReplyNotice.excerpt(reply);
    if (body.isEmpty) return;

    _remember(messageId);
    await LocalNotificationService.instance.showReplyReady(
      id: messageId.hashCode & 0x7fffffff,
      body: body,
      payload: ReplyNotice.payloadFor(conversationId),
    );
  }

  void _remember(String messageId) {
    _announced.add(messageId);
    if (_announced.length > _announcedMemory) _announced.removeAt(0);
  }

  void _open(String payload) {
    final conversationId = ReplyNotice.conversationIdFrom(payload);
    if (conversationId == null) return;
    unawaited(_openConversation(conversationId));
  }

  Future<void> _openConversation(String conversationId) async {
    await _ref
        .read(conversationControllerProvider.notifier)
        .openConversation(conversationId);
    _ref.read(appRouterProvider).go(AppRoutes.home);
  }

  void dispose() {
    unawaited(_taps?.cancel());
    _taps = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }
}
