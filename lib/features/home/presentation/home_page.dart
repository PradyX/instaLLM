import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/features/conversations/domain/message.dart';
import 'package:pocket_llm/features/conversations/domain/message_attachment.dart';
import 'package:pocket_llm/features/group_chat/application/active_room.dart';
import 'package:pocket_llm/features/group_chat/presentation/room_chat_view.dart';
import 'package:pocket_llm/features/home/domain/attachment_history.dart';
import 'package:pocket_llm/features/home/domain/readable_reply.dart';
import 'package:pocket_llm/features/conversations/presentation/conversation_controller.dart';

import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
import 'package:pocket_llm/features/documents/application/documents_controller.dart';
import 'package:pocket_llm/core/widgets/chat_bubble.dart';
import 'package:pocket_llm/core/widgets/chat_composer.dart';
import 'package:pocket_llm/core/widgets/composer_model_pill.dart';
import 'package:pocket_llm/core/widgets/composer_reasoning_pill.dart';
import 'package:pocket_llm/features/home/presentation/composer_attach_button.dart';
import 'package:pocket_llm/features/voice/application/composer_dictation_controller.dart';
import 'package:pocket_llm/features/home/presentation/composer_shortcuts.dart';
import 'package:pocket_llm/features/home/presentation/home_controller.dart';
import 'package:pocket_llm/core/navigation/app_shell.dart';
import 'package:pocket_llm/features/voice/application/tts_controller.dart';
import 'package:pocket_llm/features/voice/application/voice_conversation_controller.dart';
import 'package:pocket_llm/features/model_selection/domain/llm_model.dart';
import 'package:pocket_llm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:pocket_llm/features/personas/application/personas_controller.dart';
import 'package:pocket_llm/features/workspaces/application/workspaces_controller.dart';
import 'package:pocket_llm/features/model_selection/presentation/model_selection_state.dart';
import 'package:pocket_llm/features/tools/application/tool_approval_controller.dart';
import 'package:pocket_llm/features/tools/application/tool_registry.dart';
import 'package:pocket_llm/features/tools/presentation/tool_approval_dialog.dart';

/// What tapping an empty-state suggestion does before its prompt is prepared.
///
/// A card that names a file ("Summarize docs", "Ask about image") opens the
/// picker that file needs; the rest only prepare text.
enum _SuggestionAction {
  /// Prepare the prompt and nothing else.
  none,

  /// Index files into the knowledge collection chat retrieves from.
  pickDocuments,

  /// Attach images to the message being composed.
  pickImage,
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  bool _scrollScheduled = false;
  ProviderSubscription<List<Message>>? _messagesSubscription;
  ProviderSubscription<ModelSelectionState>? _modelSelectionSubscription;
  ProviderSubscription<String?>? _composerDraftSubscription;
  ProviderSubscription<HomeGenerationStatus>? _generationSubscription;
  ProviderSubscription<String?>? _conversationSubscription;

  /// Reply currently being read aloud, so its own button can offer a stop.
  String? _readingMessageId;
  final List<XFile> _draftImages = [];

  /// Draft images taken from this conversation's history, keyed by their
  /// stored path, so they can be sent as the copies they already are instead
  /// of being prepared again.
  final Map<String, MessageAttachment> _reusedImages = {};

  /// What the last attach action put into the knowledge collection, or null.
  ///
  /// Images already show their own preview above the composer; a picked
  /// document is indexed into the collection chat retrieves from, which left no
  /// visible trace at all — so attaching a file the collection already had
  /// looked exactly like cancelling the picker.
  String? _attachNotice;

  /// More images than this would cost more context than a local model can
  /// afford per turn, so the composer stops taking them.
  static const int _maxDraftImages = 4;

  @override
  void dispose() {
    _messagesSubscription?.close();
    _modelSelectionSubscription?.close();
    _composerDraftSubscription?.close();
    _generationSubscription?.close();
    _conversationSubscription?.close();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _messagesSubscription = ref.listenManual(homeControllerProvider, (_, next) {
      _scheduleScrollToBottom();
    });
    _composerDraftSubscription = ref.listenManual(composerDraftProvider, (
      _,
      next,
    ) {
      if (next == null) return;
      _applyComposerDraft(next);
    });
    // Text prepared while this page was not built (voice, for example) is
    // waiting in the provider when the chat opens again.
    final pendingDraft = ref.read(composerDraftProvider);
    if (pendingDraft != null) {
      _applyComposerDraft(pendingDraft);
    }

    // Reading a reply aloud follows the generation that produced it: the
    // setting is off by default, and only a run that just finished qualifies.
    _generationSubscription = ref.listenManual(homeGenerationStatusProvider, (
      previous,
      next,
    ) {
      if (previous == null) return;
      // The hands-free voice loop reads its own replies through the same
      // engine; reading them here as well would talk over it and cut the
      // loop's utterance short.
      if (ref.read(voiceConversationActiveProvider)) return;
      if (!shouldReadFinishedReply(
        wasGenerating: previous.isGenerating,
        isGenerating: next.isGenerating,
        readAloudEnabled: ref.read(voiceSettingsProvider).readRepliesAloud,
      )) {
        return;
      }

      final reply = lastReadableReply(ref.read(homeControllerProvider));
      if (reply == null) return;
      unawaited(_readReplyAloud(reply));
    });

    // A sentence about what a chat's attach added is only true for that chat.
    // Switching, starting or deleting a conversation must not leave the old
    // one sitting under the composer of a chat that never saw that file.
    _conversationSubscription = ref.listenManual(
      conversationControllerProvider.select(
        (state) => state.activeConversationId,
      ),
      (_, _) {
        if (_attachNotice == null) return;
        setState(() => _attachNotice = null);
      },
    );

    _modelSelectionSubscription = ref.listenManual(
      modelSelectionControllerProvider,
      (_, next) {
        if (_draftImages.isEmpty) return;
        if (_isVisionReady(next.selectedModel)) return;

        _clearDraftImages();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Image attachment cleared because the selected model does not support vision chat.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  bool _isVisionReady(LlmModel? model) {
    return model != null && model.isDownloaded && model.supportsVision;
  }

  /// Moves text prepared elsewhere into the message box.
  ///
  /// Speech arrives from a local model, so it is a draft like any other: it is
  /// appended to whatever the user already typed and waits there for review,
  /// instead of being sent on their behalf.
  void _applyComposerDraft(String draft) {
    ref.read(composerDraftProvider.notifier).state = null;
    final prepared = draft.trim();
    if (prepared.isEmpty) return;

    final typed = _messageController.text.trim();
    final next = typed.isEmpty ? prepared : '$typed\n$prepared';
    _messageController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _sendMessage() async {
    final generationStatus = ref.read(homeGenerationStatusProvider);
    if (generationStatus.isGenerating) return;

    final selectionState = ref.read(modelSelectionControllerProvider);
    final hasDownloadedModel = selectionState.models.any((m) => m.isDownloaded);
    if (!hasDownloadedModel) return;

    final selectedModel = selectionState.selectedModel;
    final text = _messageController.text.trim();
    final draftImages = List<XFile>.of(_draftImages);

    if (draftImages.isNotEmpty && !_isVisionReady(selectedModel)) {
      _showVisionRequiredMessage();
      return;
    }

    if (text.isEmpty) {
      if (draftImages.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Add a question before sending '
              '${draftImages.length == 1 ? 'the image' : 'the images'}.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // A desktop Return-send keeps the field ready for the next message; the
    // mobile keyboard is dismissed the way it always was.
    if (!sendsMessageOnEnter) {
      FocusScope.of(context).unfocus();
    }
    _messageController.clear();
    final reusedImages = {
      for (final file in draftImages)
        if (_reusedImages.containsKey(file.path))
          file.path: _reusedImages[file.path]!,
    };
    _clearDraftImages();
    _scheduleScrollToBottom(animated: true);

    await ref
        .read(homeControllerProvider.notifier)
        .sendMessage(
          text,
          imagePaths: [for (final file in draftImages) file.path],
          reusedAttachments: reusedImages,
        );

    if (!mounted) return;
    _scheduleScrollToBottom(animated: true);
  }

  Future<void> _pickImage(LlmModel? selectedModel) async {
    if (!_isVisionReady(selectedModel)) return;

    final remaining = _maxDraftImages - _draftImages.length;
    if (remaining <= 0) {
      _showDraftLimitMessage();
      return;
    }

    List<XFile> pickedFiles;
    try {
      pickedFiles = await _imagePicker.pickMultiImage();
    } catch (_) {
      // Some platforms only offer the single-image picker; adding one image
      // at a time still builds a multi-image message.
      final single = await _imagePicker.pickImage(source: ImageSource.gallery);
      pickedFiles = single == null ? const [] : [single];
    }
    if (pickedFiles.isEmpty) return;

    final accepted = pickedFiles.take(remaining).toList(growable: false);
    setState(() => _draftImages.addAll(accepted));

    if (pickedFiles.length > accepted.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only $_maxDraftImages images fit in one message, so the rest were '
            'not added.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Empties the composer's images, including the copies reused from history.
  void _clearDraftImages() {
    setState(() {
      _draftImages.clear();
      _reusedImages.clear();
    });
  }

  void _removeDraftImage(int index) {
    setState(() {
      _reusedImages.remove(_draftImages[index].path);
      _draftImages.removeAt(index);
    });
  }

  void _showDraftLimitMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A message can carry up to $_maxDraftImages images. Remove one to '
          'add another.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Offers the images this conversation already holds.
  ///
  /// The listed files are the copies Pocket LLM stored when they were first
  /// sent, so reusing one costs no preparation and still works when the file
  /// the user picked the first time has moved or been deleted. Copies that are
  /// no longer on the device are filtered out instead of being offered and
  /// then failing.
  Future<void> _showAttachmentHistory(
    List<AttachmentHistoryEntry> entries,
  ) async {
    if (_maxDraftImages - _draftImages.length <= 0) {
      _showDraftLimitMessage();
      return;
    }

    final available = [
      for (final entry in entries)
        if (File(entry.path).existsSync()) entry,
    ];
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Those images are no longer on this device.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final attachedPaths = {for (final file in _draftImages) file.path};
    final chosen = await showModalBottomSheet<AttachmentHistoryEntry>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _AttachmentHistorySheet(
        entries: available,
        attachedPaths: attachedPaths,
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() {
      _draftImages.add(XFile(chosen.path));
      _reusedImages[chosen.path] = chosen.attachment;
    });
  }

  /// Reads [message] aloud, or stops when it is already being read.
  Future<void> _toggleReadAloud(Message message) async {
    if (_readingMessageId == message.id &&
        ref.read(ttsControllerProvider).isSpeaking) {
      await ref.read(ttsControllerProvider.notifier).stop();
      if (mounted) setState(() => _readingMessageId = null);
      return;
    }
    await _readReplyAloud(message);
  }

  /// Holds the reply that is being read, or continues it.
  Future<void> _toggleReadingPause() async {
    final controller = ref.read(ttsControllerProvider.notifier);
    final isPaused = ref.read(ttsControllerProvider).isPaused;
    if (isPaused) {
      await controller.resume();
    } else {
      await controller.pause();
    }
  }

  /// Speaks one reply. Only one is read at a time, so starting another stops
  /// the first and the audio never overlaps.
  Future<void> _readReplyAloud(Message message) async {
    final controller = ref.read(ttsControllerProvider.notifier);
    await controller.stop();
    if (!mounted) return;

    setState(() => _readingMessageId = message.id);
    await controller.speak(message.content);
    if (mounted) setState(() => _readingMessageId = null);
  }

  Future<void> _startNewConversation() async {
    // A new chat is a conversation, so the page leaves whatever room it was
    // showing; the room keeps every line it had.
    showConversation(ref);
    await ref
        .read(conversationControllerProvider.notifier)
        .createConversation(
          activeModelId: ref
              .read(modelSelectionControllerProvider)
              .selectedModelId,
          // Record the default persona so later default changes do not alter
          // what this conversation already uses.
          personaId: ref.read(personasProvider).defaultPersonaId,
        );
  }

  Future<void> _regenerateMessage(Message message) async {
    await ref
        .read(homeControllerProvider.notifier)
        .regenerateAssistantMessage(message.id);
  }

  Future<void> _editAndResendMessage(Message message) async {
    var draftText = message.content;
    final updatedText = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit & Resend'),
          content: TextFormField(
            initialValue: message.content,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
            onChanged: (value) => draftText = value,
            decoration: const InputDecoration(
              hintText: 'Edit your message...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draftText.trim()),
              child: const Text('Resend'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (updatedText == null || updatedText.isEmpty) return;

    await ref
        .read(homeControllerProvider.notifier)
        .editAndResendMessage(message.id, updatedText);
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        maxExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(maxExtent);
    }
  }

  void _scheduleScrollToBottom({bool animated = false}) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted) return;
      _scrollToBottom(animated: animated);
    });
  }

  /// Shows the registry's permission question and reports the answer back.
  ///
  /// Closing the dialog any other way than Allow is a refusal, so a prompt
  /// that disappears can never be read as consent. If this screen is gone, the
  /// question is left to its own timeout, which also refuses.
  Future<void> _askForToolApproval(ToolApprovalRequest request) async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ToolApprovalDialog(
        request: request,
        onDecision: (value) => Navigator.of(dialogContext).pop(value),
      ),
    );
    if (!mounted) return;
    final controller = ref.read(toolApprovalControllerProvider.notifier);
    if (approved == true) {
      controller.approve();
    } else {
      controller.deny();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(homeControllerProvider);
    final generationStatus = ref.watch(homeGenerationStatusProvider);
    ref.listen<ToolApprovalRequest?>(toolApprovalControllerProvider, (
      previous,
      next,
    ) {
      if (next == null) return;
      unawaited(_askForToolApproval(next));
    });
    final selectionState = ref.watch(modelSelectionControllerProvider);
    final selectedModel = selectionState.selectedModel;
    // The models a chat can answer with, as every other composer reads them.
    // Embedding models are installed models too, but they cannot answer a
    // chat: they are offered where a collection chooses how it searches.
    final downloadedModels = ref.watch(chatModelsProvider);
    final hasDownloadedModel = downloadedModels.isNotEmpty;
    final canAttachImage = _isVisionReady(selectedModel);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isGenerating = generationStatus.isGenerating;
    final generationText = generationStatus.statusText;
    final ttsState = ref.watch(ttsControllerProvider);
    // Option C: dock the sidebar on wide screens, keep the drawer narrow.
    final isWide = MediaQuery.of(context).size.width >= 900;
    // One page, two kinds of chat: a room when one is open, the conversation
    // otherwise. The room's own lines and controls are [RoomChatView]'s; the
    // header, sidebar and composer slots below belong to both.
    final room = ref.watch(activeRoomProvider);

    return AppShell(
      section: room == null
          ? AppSection.chats
          : room.isDirect
          ? AppSection.bots
          : AppSection.rooms,
      leading: ShellChatLeading(isGenerating: isGenerating),
      isGenerating: isGenerating,
      child: Scaffold(
        appBar: AppBar(
          // A conversation needs no title: the chat is the whole surface. A
          // room names itself and the rooms/bots section it belongs to.
          toolbarHeight: 56,
          title: room == null ? null : RoomHeaderTitle(room: room),
          leadingWidth: 42,
          actionsPadding: const EdgeInsets.only(right: 12),
          leading: isWide
              ? null
              : room != null
              ? Center(
                  child: _toolbarIconButton(
                    context,
                    tooltip: 'Back to chat',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => showConversation(ref),
                  ),
                )
              : Builder(
                  builder: (drawerContext) => Center(
                    child: _toolbarIconButton(
                      context,
                      tooltip: 'Menu',
                      icon: Icons.menu_rounded,
                      onPressed: () => Scaffold.of(drawerContext).openDrawer(),
                    ),
                  ),
                ),
          actions: [
            // Only what is open has settings: a bot's own settings for a
            // direct room, the room's mode, members and rounds for a group.
            if (room != null)
              _toolbarIconButton(
                context,
                tooltip: 'Settings',
                icon: Icons.settings_outlined,
                onPressed: () => showRoomSettings(context, room.id),
              ),
            if (room != null) const SizedBox(width: 6),
            _toolbarIconButton(
              context,
              tooltip: 'New chat',
              icon: Icons.add_comment_outlined,
              onPressed: isGenerating ? null : _startNewConversation,
            ),
          ],
        ),
        drawer: isWide
            ? null
            : _buildDrawer(context, colorScheme, textTheme, selectedModel),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: room != null
                ? RoomChatView(key: ValueKey(room.id), chatId: room.id)
                : Column(
                    children: [
                      Expanded(
                        child: messages.isEmpty
                            ? _buildEmptyState(context, colorScheme, textTheme)
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (context, index) {
                                  final message = messages[index];
                                  return ChatBubble(
                                    message: message,
                                    onRegenerate:
                                        (!isGenerating && !message.isUser)
                                        ? () => _regenerateMessage(message)
                                        : null,
                                    onEditResend:
                                        (!isGenerating &&
                                            message.isUser &&
                                            message.attachments.isEmpty)
                                        ? () => _editAndResendMessage(message)
                                        : null,
                                    onReadAloud:
                                        (ttsState.isSupported &&
                                            !message.isUser &&
                                            message.content.trim().isNotEmpty)
                                        ? () => _toggleReadAloud(message)
                                        : null,
                                    isReading:
                                        ttsState.isSpeaking &&
                                        _readingMessageId == message.id,
                                    isPaused: ttsState.isPaused,
                                    onPauseReading: () => _toggleReadingPause(),
                                  );
                                },
                              ),
                      ),
                      _buildInputBar(
                        context,
                        colorScheme,
                        textTheme,
                        isGenerating,
                        generationText,
                        hasDownloadedModel,
                        canAttachImage,
                        selectedModel,
                        downloadedModels,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Runs an empty-state suggestion: the picker it implies first, then the
  /// prompt it prepares.
  ///
  /// The prompt is only placed in the composer once the picker produced
  /// something, so cancelling one leaves the composer exactly as it was. Both
  /// pickers are the app's own: images become draft attachments, documents are
  /// indexed into the knowledge collection chat retrieves from.
  Future<void> _runSuggestion(
    _SuggestionAction action,
    String prompt,
    LlmModel? selectedModel,
  ) async {
    switch (action) {
      case _SuggestionAction.none:
        break;
      case _SuggestionAction.pickImage:
        if (!_isVisionReady(selectedModel)) {
          _showVisionRequiredMessage();
          return;
        }
        await _pickImage(selectedModel);
        if (!mounted || _draftImages.isEmpty) return;
        break;
      case _SuggestionAction.pickDocuments:
        final attached = await _attachDocuments();
        if (!attached) return;
        break;
    }

    _fillComposer(prompt);
  }

  /// Opens the document picker and reports what it added to the knowledge
  /// collection.
  ///
  /// Returns true when the user chose at least one file. The count comes from
  /// the picker itself rather than from the library, because a file that is
  /// already indexed adds nothing and would otherwise read as a cancel.
  Future<bool> _attachDocuments() async {
    // The chat has to exist before the file is indexed: a document belongs to
    // the chat it was added from, and deleting that chat is what forgets it.
    final conversationId = await ref
        .read(homeControllerProvider.notifier)
        .ensureActiveConversation();
    if (!mounted) return false;

    final notifier = ref.read(documentsProvider.notifier);
    final chosen = await notifier.pickDocuments(
      addedByConversationId: conversationId,
    );
    if (!mounted) return false;

    final documents = ref.read(documentsProvider);
    final error = documents.errorMessage;
    if (error != null) {
      notifier.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return false;
    }
    if (chosen == 0) return false;

    // The library's own sentence already says whether the file was indexed or
    // was already up to date, so the notice cannot drift from what happened.
    final status = documents.statusMessage;
    notifier.clearStatus();
    if (status != null) {
      setState(() => _attachNotice = status);
    }
    return true;
  }

  /// Explains that the selected model cannot take an image.
  void _showVisionRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Choose a downloaded vision-capable model before sending an image.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Fills the composer with a suggestion so it waits for review, exactly
  /// like a draft prepared anywhere else.
  void _fillComposer(String prompt) {
    _messageController.value = TextEditingValue(
      text: prompt,
      selection: TextSelection.collapsed(offset: prompt.length),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final selectionState = ref.watch(modelSelectionControllerProvider);
    final hasDownloadedModel = selectionState.models.any((m) => m.isDownloaded);
    final selectedModel = selectionState.selectedModel;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    // Without a model there is nothing to chat with yet: keep the onboarding
    // path to model selection instead of the greeting.
    if (!hasDownloadedModel) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.download_for_offline_rounded,
                  size: 40,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No models ready',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You need to download a model before you can start chatting.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.modelSelection),
                icon: const Icon(Icons.settings_suggest_rounded),
                label: const Text('Go to Model Selection'),
              ),
            ],
          ),
        ),
      );
    }

    // Option A: a centered greeting with tappable suggestion cards, so the
    // empty chat reads like a standard chat app. A card that implies a file
    // opens that picker first and only then prepares its prompt.
    const suggestions = [
      (
        icon: Icons.edit_outlined,
        title: 'Draft an email',
        subtitle: 'to my landlord\u2026',
        prompt: 'Help me draft a polite email to my landlord about ',
        action: _SuggestionAction.none,
      ),
      (
        icon: Icons.folder_copy_outlined,
        title: 'Summarize docs',
        subtitle: 'from my knowledge\u2026',
        prompt: 'Summarize the key points from my documents about ',
        action: _SuggestionAction.pickDocuments,
      ),
      (
        icon: Icons.lightbulb_outline_rounded,
        title: 'Brainstorm',
        subtitle: 'ideas for\u2026',
        prompt: 'Brainstorm 5 creative ideas for ',
        action: _SuggestionAction.none,
      ),
      (
        icon: Icons.add_photo_alternate_outlined,
        title: 'Ask about image',
        subtitle: 'attach, then ask\u2026',
        prompt: 'What do you see in this image? ',
        action: _SuggestionAction.pickImage,
      ),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.smart_toy_rounded,
                size: 32,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              greeting,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Running 100% on-device \u00b7 private to you',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: [
                for (final suggestion in suggestions)
                  Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => unawaited(
                        _runSuggestion(
                          suggestion.action,
                          suggestion.prompt,
                          selectedModel,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  suggestion.icon,
                                  size: 15,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    suggestion.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              suggestion.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    bool isGenerating,
    String generationText,
    bool hasDownloadedModel,
    bool canAttachImage,
    LlmModel? selectedModel,
    List<LlmModel> downloadedModels,
  ) {
    final canCompose = hasDownloadedModel && !isGenerating;
    final progressText = generationText.isEmpty
        ? 'Assistant is responding...'
        : generationText;
    final historyImages = collectImageHistory(
      ref.watch(homeControllerProvider),
    );

    // Reference bar: text on top, one action row at the bottom, and the
    // context readout below the card.

    // The model pill moved down from the toolbar: the composer owns model
    // switching now, and reads the same "what is selected" answer a room does.
    final pillModel = ref.watch(selectedChatModelProvider);
    // Dictation errors surface once, where the mic was tapped.
    ref.listen<DictationState>(composerDictationProvider, (previous, next) {
      final error = next.errorMessage;
      if (error != null && error != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
        );
      }
    });
    final dictation = ref.watch(composerDictationProvider);
    // The context readout under the card: the running request's own budget
    // while generating, otherwise what the next request would cost.
    final projection = ref.watch(homeContextProjectionProvider);
    final generationUsage = ref.watch(
      homeGenerationStatusProvider.select((s) => s.contextUsage),
    );
    final meterUsage = isGenerating
        ? generationUsage ?? projection?.usage
        : projection?.usage;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChatComposer(
            controller: _messageController,
            enabled: canCompose,
            hintText: !hasDownloadedModel
                ? 'Download a model to start chatting...'
                : isGenerating
                ? 'Wait for current response...'
                : canAttachImage
                ? 'Ask about your image or start a chat...'
                : 'Message Pocket LLM...',
            onSend: _sendMessage,
            sendsOnEnter: sendsMessageOnEnter,
            header: (isGenerating || _draftImages.isNotEmpty)
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isGenerating)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 8,
                            left: 8,
                            right: 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  progressText,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  ref
                                      .read(homeControllerProvider.notifier)
                                      .stopGeneration();
                                },
                                icon: const Icon(
                                  Icons.stop_circle_outlined,
                                  size: 18,
                                ),
                                label: const Text('Stop'),
                                style: TextButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_draftImages.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildDraftImagesPreview(
                            context,
                            colorScheme,
                            textTheme,
                          ),
                        ),
                    ],
                  )
                : null,
            leading: ComposerModelPill(
              models: downloadedModels,
              selected: pillModel,
              enabled: !isGenerating,
              onSelected: (next) => ref
                  .read(modelSelectionControllerProvider.notifier)
                  .selectModel(next),
              onEmptyPressed: () => context.push(AppRoutes.modelSelection),
            ),
            reasoning: ComposerReasoningControl(
              modelId: pillModel?.id ?? '',
              enabled: !isGenerating,
            ),
            middle: hasDownloadedModel
                ? ComposerAttachButton(
                    enabled: canCompose,
                    canAttachImage: canAttachImage,
                    hasHistoryImages: historyImages.isNotEmpty,
                    onPickImage: () => _pickImage(selectedModel),
                    onPickHistory: () => _showAttachmentHistory(historyImages),
                    onAttachFiles: () => unawaited(_attachDocuments()),
                  )
                : null,
            onMicPressed: () => unawaited(
              ref
                  .read(composerDictationProvider.notifier)
                  .toggle(_messageController),
            ),
            micState: dictation.microphone,
          ),
          if (_attachNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildAttachNotice(context, colorScheme, textTheme),
            ),
          if (hasDownloadedModel && meterUsage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Context: ${_formatTokens(meterUsage.usedTokens)}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One 34px toolbar button, shared by the menu, a room's settings and new
  /// chat so no two can differ in size or shape. The SizedBox pins the size
  /// instead of trusting button defaults.
  ///
  /// The button is an outlined icon in the accent colour with nothing behind
  /// it: a row of filled grey squares read as buttons competing with the
  /// composer, and the tint said "pressed" at rest. Hover and press still get
  /// the ripple, which is enough feedback for an icon that names itself.
  Widget _toolbarIconButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: colorScheme.primary,
          disabledForegroundColor: colorScheme.primary.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// Says what the last attach action added, so every attach path leaves
  /// something visible behind it.
  Widget _buildAttachNotice(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.library_add_check_outlined,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _attachNotice!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _attachNotice = null),
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
        ],
      ),
    );
  }

  /// Compact token count for the context line under the composer (1.5K).
  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${_trimNumber(tokens / 1000000)}M';
    if (tokens >= 1000) return '${_trimNumber(tokens / 1000)}K';
    return '$tokens';
  }

  String _trimNumber(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  Widget _buildDraftImagesPreview(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final count = _draftImages.length;
    final reusedCount = _reusedImages.length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  count == 1 ? '1 image attached' : '$count images attached',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count > 1)
                TextButton(
                  onPressed: _clearDraftImages,
                  child: const Text('Clear all'),
                ),
            ],
          ),
          if (reusedCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              reusedCount == 1
                  ? '1 image is a copy this chat already stores and is sent as '
                        'it is.'
                  : '$reusedCount images are copies this chat already stores '
                        'and are sent as they are.',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var index = 0; index < count; index++)
                _DraftImageThumb(
                  file: _draftImages[index],
                  onRemove: () => _removeDraftImage(index),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A section name inside the drawer, above the rows it introduces.
  Widget _drawerLabel(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.08,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
    dynamic selectedModel,
  ) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: colorScheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/icons/pocketllm_new.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pocket LLM',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'On-device AI Chat',
                  style: TextStyle(
                    color: colorScheme.onPrimary.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('Conversations'),
            subtitle: const Text('Search, rename and manage chats'),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.conversations);
            },
          ),
          // Narrow screens have no rail, so the drawer carries the same bots
          // and rooms: each row opens that chat on this page.
          _drawerLabel(context, 'Bots'),
          BotChatRows(
            workspaceId: ref.read(workspacesProvider).active?.id,
            onOpened: () => Navigator.pop(context),
          ),
          _drawerLabel(context, 'Rooms'),
          RoomChatRows(
            workspaceId: ref.read(workspacesProvider).active?.id,
            onOpened: () => Navigator.pop(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Model Selection'),
            subtitle: selectedModel != null
                ? Text(
                    '${selectedModel.name} · ${selectedModel.parameterSize}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                : const Text('No model selected'),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.modelSelection);
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: const Text('Benchmark'),
            subtitle: const Text('Compare local models and run llmfit'),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.benchmark);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.about);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.settings);
            },
          ),
        ],
      ),
    );
  }
}

/// One pending image in the composer, with a remove button.
/// Images this conversation already holds, offered for reuse.
class _AttachmentHistorySheet extends StatelessWidget {
  const _AttachmentHistorySheet({
    required this.entries,
    required this.attachedPaths,
  });

  final List<AttachmentHistoryEntry> entries;
  final Set<String> attachedPaths;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Images from this chat', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'A reused image is the copy stored with the original message, so '
              'it is not prepared again and stays available even when the '
              'picked file has moved.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isAttached = attachedPaths.contains(entry.path);
                  return _HistoryImageTile(
                    entry: entry,
                    isAttached: isAttached,
                    onTap: isAttached
                        ? null
                        : () => Navigator.of(context).pop(entry),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryImageTile extends StatelessWidget {
  const _HistoryImageTile({
    required this.entry,
    required this.isAttached,
    required this.onTap,
  });

  final AttachmentHistoryEntry entry;
  final bool isAttached;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Image.file(
                  File(entry.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isAttached ? 'Already attached' : 'Attach this copy',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!isAttached)
              Icon(Icons.add_circle_outline, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _DraftImageThumb extends StatelessWidget {
  const _DraftImageThumb({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageFile = File(file.path);
    final imageExists = imageFile.existsSync();
    final label = p.basename(file.path);

    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: imageExists
                      ? Image.file(imageFile, fit: BoxFit.cover)
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                          ),
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: colorScheme.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: Tooltip(
                      message: 'Remove image',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 64,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
