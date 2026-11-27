import 'package:installm/features/skills/presentation/skill_context_details.dart';
import 'package:installm/features/skills/application/skill_choices.dart';
import 'package:installm/features/skills/application/skills_controller.dart';
import 'package:installm/features/memory/application/memory_controller.dart';
import 'package:installm/features/kanban/application/kanban_controller.dart'
    show activeWorkspaceIdProvider;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/features/artifacts/data/chat_export.dart';
import 'package:installm/features/artifacts/data/chat_export_store.dart';
import 'package:installm/features/conversations/domain/message.dart';
import 'package:installm/features/conversations/domain/message_attachment.dart';
import 'package:installm/features/group_chat/application/active_room.dart';
import 'package:installm/features/group_chat/presentation/room_chat_view.dart';
import 'package:installm/features/home/domain/attachment_history.dart';
import 'package:installm/features/home/domain/readable_reply.dart';
import 'package:installm/features/conversations/presentation/conversation_controller.dart';

import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/documents/application/documents_controller.dart';
import 'package:installm/core/widgets/chat_bubble.dart';
import 'package:installm/core/widgets/chat_composer.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/features/home/presentation/composer_attach_button.dart';
import 'package:installm/features/voice/application/composer_dictation_controller.dart';
import 'package:installm/features/home/presentation/composer_shortcuts.dart';
import 'package:installm/core/nudges/post_reply_nudge.dart';
import 'package:installm/features/home/presentation/home_controller.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/features/voice/application/tts_controller.dart';
import 'package:installm/features/voice/application/voice_conversation_controller.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/share/application/assist_ask_provider.dart';
import 'package:installm/features/share/application/assist_launch_provider.dart';
import 'package:installm/features/share/application/draft_attachments_provider.dart';
import 'package:installm/features/share/application/process_text_provider.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/features/share/domain/shared_payload.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';
import 'package:installm/features/personas/application/personas_controller.dart';
import 'package:installm/features/model_selection/presentation/model_selection_state.dart';
import 'package:installm/features/tools/application/tool_approval_controller.dart';
import 'package:installm/features/tools/application/tool_registry.dart';
import 'package:installm/features/tools/presentation/tool_approval_dialog.dart';
import 'package:installm/i18n/strings.g.dart';

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

  /// The composer's field, so an assistant launch can put the caret in it
  /// (Road Map 5 Phase 5.3).
  final FocusNode _composerFocusNode = FocusNode();
  final _imagePicker = ImagePicker();
  bool _scrollScheduled = false;
  ProviderSubscription<List<Message>>? _messagesSubscription;
  ProviderSubscription<ModelSelectionState>? _modelSelectionSubscription;
  ProviderSubscription<String?>? _composerDraftSubscription;
  ProviderSubscription<HomeGenerationStatus>? _generationSubscription;
  ProviderSubscription<HomeGenerationStatus>? _starPromptSubscription;
  ProviderSubscription<String?>? _conversationSubscription;
  ProviderSubscription<List<SharedAttachment>>? _draftAttachmentsSubscription;
  ProviderSubscription<int>? _assistLaunchSubscription;
  ProviderSubscription<int>? _assistAskSubscription;

  /// Reply currently being read aloud, so its own button can offer a stop.
  String? _readingMessageId;

  /// An assistant launch wanted the composer while it was locked (a reply was
  /// still streaming, or no model was ready). The request waits for the field
  /// to be usable instead of being dropped.
  bool _pendingComposerFocus = false;
  final List<XFile> _draftImages = [];

  /// Documents (a PDF another app shared) waiting to travel with the next
  /// message. They are indexed into the knowledge collection when sent, so the
  /// model reads their text, and the file itself is attached to the message.
  final List<SharedAttachment> _draftDocuments = [];

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

  /// Two documents fit one message; more is a knowledge import, not an
  /// attachment.
  static const int _maxDraftDocuments = 2;

  /// True while the message being composed carries an image or a document.
  bool get _hasDraftAttachments =>
      _draftImages.isNotEmpty || _draftDocuments.isNotEmpty;

  @override
  void dispose() {
    _messagesSubscription?.close();
    _modelSelectionSubscription?.close();
    _composerDraftSubscription?.close();
    _generationSubscription?.close();
    _starPromptSubscription?.close();
    _conversationSubscription?.close();
    _draftAttachmentsSubscription?.close();
    _assistLaunchSubscription?.close();
    _assistAskSubscription?.close();
    _composerFocusNode.dispose();
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
    // Text and files prepared while this page was not built (voice, a share, a
    // link) are waiting in their providers when the chat opens again. Taking
    // them consumes the draft, and a provider cannot be modified while the tree
    // is still building, so it happens once the first frame is done.
    _draftAttachmentsSubscription = ref.listenManual(draftAttachmentsProvider, (
      _,
      next,
    ) {
      if (next.isEmpty) return;
      _consumeStagedAttachments();
    });
    // Summoning the assistant brings no content: it asks for the composer,
    // which is where the user can type. A cold start already has the count set
    // before this page builds, so the same subscription covers both cases.
    _assistLaunchSubscription = ref.listenManual(assistLaunchProvider, (
      _,
      next,
    ) {
      if (next > 0) _focusComposer();
    });
    // A question sent from the assistant's floating panel has already been
    // asked, so the chat asks it once its draft is in the composer.
    _assistAskSubscription = ref.listenManual(assistAskProvider, (_, next) {
      if (next > 0) unawaited(_askFromAssistant());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pendingDraft = ref.read(composerDraftProvider);
      if (pendingDraft != null) _applyComposerDraft(pendingDraft);
      _consumeStagedAttachments();
      if (ref.read(assistLaunchProvider) > 0) _focusComposer();
      if (ref.read(assistAskProvider) > 0) unawaited(_askFromAssistant());
    });

    // Reading a reply aloud follows the generation that produced it: the
    // setting is off by default, and only a run that just finished qualifies.
    _generationSubscription = ref.listenManual(homeGenerationStatusProvider, (
      previous,
      next,
    ) {
      if (_pendingComposerFocus && !next.isGenerating) _focusComposer();
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

    // The GitHub star reminder only looks at a reply that actually finished;
    // it is rate limited and never appears while text is still streaming.
    _starPromptSubscription = ref.listenManual(homeGenerationStatusProvider, (
      previous,
      next,
    ) {
      if (previous == null || !previous.isGenerating) return;
      if (next.isGenerating || next.generatedTokens <= 0) return;
      unawaited(maybeNudgeAfterReply(context, ref));
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
    ref.read(composerDraftProvider.notifier).setDraft(null);
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

  /// Sends a question the assistant's panel already asked.
  ///
  /// The panel opens the chat from nothing, so the model list can still be
  /// loading when the question arrives, and a send at that moment would answer
  /// "no model selected". The question waits for a downloaded model instead of
  /// failing on a race the user cannot see.
  Future<void> _askFromAssistant() async {
    for (var attempt = 0; attempt < 50; attempt++) {
      if (!mounted) return;
      final model = ref.read(modelSelectionControllerProvider).selectedModel;
      if (model != null && model.isDownloaded) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    await _sendMessage();
  }

  Future<void> _sendMessage() async {
    final generationStatus = ref.read(homeGenerationStatusProvider);
    if (generationStatus.isGenerating) return;

    final selectionState = ref.read(modelSelectionControllerProvider);

    final selectedModel = selectionState.selectedModel;
    final text = _messageController.text.trim();
    final draftImages = List<XFile>.of(_draftImages);
    final draftDocuments = List<SharedAttachment>.of(_draftDocuments);

    if (draftImages.isNotEmpty && !_isVisionReady(selectedModel)) {
      _showVisionRequiredMessage();
      return;
    }

    if (text.isEmpty) {
      final attachmentCount = draftImages.length + draftDocuments.length;
      if (attachmentCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              attachmentCount == 1
                  ? 'Add a question before sending the attachment.'
                  : 'Add a question before sending the attachments.',
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
    _clearDraftDocuments();
    _scheduleScrollToBottom(animated: true);

    // The file is indexed first so the reply to this very message can retrieve
    // it; a failure is reported but never stops the file from being attached.
    if (draftDocuments.isNotEmpty) {
      await _indexSharedDocuments(draftDocuments);
    }

    await ref
        .read(homeControllerProvider.notifier)
        .sendMessage(
          text,
          imagePaths: [for (final file in draftImages) file.path],
          reusedAttachments: reusedImages,
          documentPaths: [for (final document in draftDocuments) document.path],
          documentLabels: [
            for (final document in draftDocuments) document.name,
          ],
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

  /// Moves files another app shared into the message being composed.
  ///
  /// Images join the composer's images, so the existing preview, removal and
  /// send paths apply to them; a vision model is still required to send them
  /// and the send says so. Documents wait beside them and are indexed into the
  /// knowledge collection when the message is sent.
  void _consumeStagedAttachments() {
    final staged = ref.read(draftAttachmentsProvider.notifier).take();
    if (staged.isEmpty || !mounted) return;

    final images = <XFile>[];
    final documents = <SharedAttachment>[];
    for (final attachment in staged) {
      if (attachment.isImage) {
        if (_draftImages.length + images.length < _maxDraftImages) {
          images.add(XFile(attachment.path));
        }
      } else if (_draftDocuments.length + documents.length <
          _maxDraftDocuments) {
        documents.add(attachment);
      }
    }

    if (images.isEmpty && documents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A message carries up to $_maxDraftImages images and '
            '$_maxDraftDocuments documents, so what was shared did not fit. '
            'Send this one first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _draftImages.addAll(images);
      _draftDocuments.addAll(documents);
    });
  }

  /// Puts the caret in the composer once it has been laid out.
  ///
  /// The assistant launch can arrive before this page has ever been shown, so
  /// the request waits for a frame and is skipped if the field is disabled (no
  /// model yet), where focusing it would only raise an empty keyboard.
  void _focusComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_composerFocusNode.canRequestFocus) {
        // Still generating, or no model is ready: the field is disabled, so the
        // request is kept until the generation listener sees it unlock.
        _pendingComposerFocus = true;
        return;
      }
      _pendingComposerFocus = false;
      _composerFocusNode.requestFocus();
    });
  }

  /// Hands the answer back to the app the selection came from.
  ///
  /// The platform refuses this for a read-only selection, so the button is
  /// never shown for one; a refusal still says so instead of pretending the
  /// text was replaced.
  Future<void> _replaceSelection(String answer) async {
    final replaced = await ref
        .read(sharedContentReceiverProvider)
        .returnProcessedText(answer);
    if (!mounted) return;
    if (!replaced) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This selection is read-only, so the answer stays in this chat.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    ref.read(processTextRequestProvider.notifier).clear();
  }

  /// Empties the composer's images, including the copies reused from history.
  void _clearDraftImages() {
    setState(() {
      _draftImages.clear();
      _reusedImages.clear();
    });
  }

  void _clearDraftDocuments() {
    if (_draftDocuments.isEmpty) return;
    setState(_draftDocuments.clear);
  }

  void _removeDraftDocument(int index) {
    setState(() => _draftDocuments.removeAt(index));
  }

  /// Indexes shared documents into the collection chat retrieves from.
  ///
  /// The file is attached to the message either way: a collection that cannot
  /// be written to (no embedding model yet, for example) is reported in the
  /// words the documents library already uses, and never silently drops the
  /// attachment.
  Future<void> _indexSharedDocuments(List<SharedAttachment> documents) async {
    final conversationId = await ref
        .read(homeControllerProvider.notifier)
        .ensureActiveConversation();
    if (conversationId == null || !mounted) return;

    final notifier = ref.read(documentsProvider.notifier);
    for (final document in documents) {
      await notifier.addDocument(
        document.path,
        name: document.name,
        addedByConversationId: conversationId,
      );
      final error = ref.read(documentsProvider).errorMessage;
      if (error == null) continue;
      notifier.clearError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error The file is still attached to this message.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final status = ref.read(documentsProvider).statusMessage;
    notifier.clearStatus();
    if (status != null && mounted) setState(() => _attachNotice = status);
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
  /// The listed files are the copies InstaLLM stored when they were first
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

  /// Saves the open conversation as a file the user picks (Road Map 5 Phase
  /// 5.0). A platform without a save dialog falls back to the app's own
  /// `exports` folder, and the notice always says where the file landed.
  Future<void> _exportActiveChat(ChatExportFormat format) async {
    final messages = ref.read(homeControllerProvider);
    if (messages.isEmpty) return;
    final title =
        ref.read(conversationControllerProvider).activeConversation?.title ??
        'Chat';
    final bytes = ChatExport.build(
      format: format,
      title: title,
      messages: messages,
    );
    final fileName = ChatExport.fileName(title: title, format: format);
    // Android has no save dialog, and the app's own folder is invisible to a
    // viewer, so the file goes into Downloads where another program can open
    // it. Everywhere else the user's own save dialog decides, and a platform
    // without one falls back to the app's exports folder.
    ChatExportLocation? saved = await ChatExportStore.saveToDownloads(
      name: fileName,
      format: format,
      bytes: bytes,
    );
    if (saved == null) {
      try {
        final location = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            XTypeGroup(label: format.label, extensions: [format.extension]),
          ],
        );
        if (location == null) return; // the user cancelled; nothing was written
        final file = File(location.path);
        await file.writeAsBytes(bytes, flush: true);
        saved = ChatExportLocation(path: file.path, label: file.path);
      } on UnimplementedError {
        saved = await _writeExportToAppFolder(fileName, bytes);
      } catch (_) {
        saved = await _writeExportToAppFolder(fileName, bytes);
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved to ${saved.label}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () async {
            final opened = await ChatExportStore.open(
              location: saved!,
              format: format,
            );
            if (opened || !mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text('No app here can open a ${format.label} file.'),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<ChatExportLocation> _writeExportToAppFolder(
    String fileName,
    Uint8List bytes,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'exports'));
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return ChatExportLocation(path: file.path, label: file.path);
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
    // True while an app is waiting for an answer it can put back into an
    // editable selection (Ask with InstaLLM). A read-only selection, and no
    // request at all, both leave it false.
    final canReplaceSelection = ref.watch(processTextRequestProvider) == false;
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
    final isWide = MediaQuery.of(context).size.width >= AppShell.wideBreakpoint;
    // One page, two kinds of chat: a room when one is open, the conversation
    // otherwise. The room's own lines and controls are [RoomChatView]'s; the
    // header, sidebar and composer slots below belong to both.
    final room = ref.watch(activeRoomProvider);
    final section = room == null
        ? AppSection.chats
        : room.isDirect
        ? AppSection.bots
        : AppSection.rooms;

    return AppShell(
      section: section,
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
            if (room == null && messages.isNotEmpty) ...[
              PopupMenuButton<ChatExportFormat>(
                tooltip: 'Save chat as',
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(Icons.save_alt_rounded, color: colorScheme.primary),
                onSelected: _exportActiveChat,
                itemBuilder: (context) => [
                  for (final format in ChatExportFormat.values)
                    PopupMenuItem(
                      value: format,
                      child: Text('Save as ${format.label}'),
                    ),
                ],
              ),
              const SizedBox(width: 6),
            ],
            if (room != null && !room.isDirect) const SizedBox(width: 6),
            if (room?.isDirect != true)
              _toolbarIconButton(
                context,
                tooltip: 'New chat',
                icon: Icons.add,
                onPressed: isGenerating ? null : _startNewConversation,
              ),
          ],
        ),
        drawer: isWide
            ? null
            : AppNavigationDrawer(section: section, isGenerating: isGenerating),
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
                                        (!isGenerating && message.isAssistant)
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
                                    // Ask with InstaLLM: an editable selection
                                    // can be replaced by this answer, so the
                                    // caller gets a way to hand it back. A
                                    // read-only one never shows this.
                                    extraActions:
                                        canReplaceSelection &&
                                            message.isAssistant &&
                                            index == messages.length - 1
                                        ? [
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _replaceSelection(
                                                    message.content,
                                                  ),
                                              icon: const Icon(
                                                Icons
                                                    .subdirectory_arrow_left_rounded,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Replace selection',
                                              ),
                                            ),
                                          ]
                                        : const [],
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
            Image.asset(
              'assets/icons/installm.png',
              width: 64,
              height: 64,
              semanticLabel: 'InstaLLM',
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
    final skills = ref.watch(skillsProvider);
    final memory = ref.watch(memoryProvider);
    final conversationId = ref
        .watch(conversationControllerProvider)
        .activeConversationId;
    final workspaceId =
        memory.conversationWorkspaces[conversationId] ??
        (memory.isReady && memory.errorMessage == null && !memory.isReadOnly
            ? ref.watch(activeWorkspaceIdProvider)
            : null);
    final canCompose = !isGenerating;
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
            commands: _hasDraftAttachments || !skills.isReady
                ? const []
                : SkillCommand.options(
                    skills.skills
                        .where(
                          (skill) =>
                              eligibleSkill(skill, workspaceId: workspaceId),
                        )
                        .toList(),
                  ),
            controller: _messageController,
            focusNode: _composerFocusNode,
            enabled: canCompose,
            hintText: !hasDownloadedModel
                ? t.memory.noModelHint
                : isGenerating
                ? 'Wait for current response...'
                : canAttachImage
                ? 'Ask about your image or start a chat...'
                : t.skills.chatHint,
            onSend: _sendMessage,
            sendsOnEnter: sendsMessageOnEnter,
            header: (isGenerating || _hasDraftAttachments)
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
                      if (_draftDocuments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildDraftDocumentsPreview(
                            context,
                            colorScheme,
                            textTheme,
                          ),
                        ),
                    ],
                  )
                : null,
            leading: ComposerModelControl(
              models: downloadedModels,
              selected: pillModel,
              enabled: !isGenerating,
              onSelected: (next) => ref
                  .read(modelSelectionControllerProvider.notifier)
                  .selectModel(next),
              onEmptyPressed: () => context.push(AppRoutes.modelSelection),
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
                  SkillContextDetails(
                    sessionKey:
                        'conversation:${ref.watch(conversationControllerProvider).activeConversationId}',
                    child: Text(
                      'Context: ${_formatTokens(meterUsage.usedTokens)}',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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

  /// Pending documents in the composer, each removable before sending.
  Widget _buildDraftDocumentsPreview(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final count = _draftDocuments.length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1 ? '1 document attached' : '$count documents attached',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'The text is indexed when you send, so the reply can read it.',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < count; index++)
                InputChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      _draftDocuments[index].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  tooltip: 'Remove this document',
                  onDeleted: () => _removeDraftDocument(index),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
            ],
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
