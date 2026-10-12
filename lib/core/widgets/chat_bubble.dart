import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_llm/features/conversations/domain/message.dart';
import 'package:pocket_llm/features/conversations/domain/message_source.dart';
import 'package:pocket_llm/features/conversations/domain/message_tool_activity.dart';
import 'package:pocket_llm/features/documents/application/documents_controller.dart';

/// One message in a chat, as the app draws it everywhere.
///
/// Home and a room share this widget so a bot's answer sits in the same bubble
/// as the assistant's, with the same code blocks, tool activity, citations and
/// actions. The room supplies what its own lines carry: [authorLabel] names the
/// bot that spoke where home says "Assistant", and [below] holds the room's
/// pending-reply card under the text.
class ChatBubble extends StatefulWidget {
  final Message message;

  /// Who this bubble is from, above the text. Home says "Assistant"; a room
  /// names the bot that spoke, because a room has several.
  final String authorLabel;

  /// Extra buttons in the bubble's action row, after the shared ones. A room
  /// puts its line actions here.
  final List<Widget> extraActions;

  /// Anything the caller draws at the end of the bubble, still inside it: a
  /// room's pending-reply card.
  final Widget? below;

  final VoidCallback? onRegenerate;
  final VoidCallback? onEditResend;

  /// Reads this message aloud, or stops it; null when the platform cannot
  /// speak or the message has nothing to say.
  final VoidCallback? onReadAloud;

  /// True while this message is the one being read.
  final bool isReading;

  /// True while that reading is held where it is; the pause action then
  /// continues it instead.
  final bool isPaused;

  /// Holds the reading or continues it. Only shown while [isReading].
  final VoidCallback? onPauseReading;

  const ChatBubble({
    super.key,
    required this.message,
    this.authorLabel = 'Assistant',
    this.extraActions = const [],
    this.below,
    this.onRegenerate,
    this.onEditResend,
    this.onReadAloud,
    this.isReading = false,
    this.isPaused = false,
    this.onPauseReading,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isUser = widget.message.isUser;
    final hasExternalUserEdit =
        isUser &&
        widget.onEditResend != null &&
        widget.message.attachments.isEmpty;
    final text = widget.message.content;
    final actionForeground = isUser
        ? colorScheme.onPrimary
        : colorScheme.primary;
    final actionBorder = isUser
        ? colorScheme.onPrimary.withValues(alpha: 0.45)
        : colorScheme.outline;
    final hasCodeFences = !isUser && text.contains('```');
    final isLongMessage =
        !hasCodeFences &&
        (text.length > 1000 || '\n'.allMatches(text).length > 50);

    final bubble = Container(
      margin: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isUser ? (hasExternalUserEdit ? 0 : 64) : 0,
        right: isUser ? 0 : 64,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.authorLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          for (
            var index = 0;
            index < widget.message.imageAttachments.length;
            index++
          ) ...[
            _MessageImage(
              imagePath: widget.message.imageAttachments[index].path,
              imageLabel: widget.message.imageAttachments[index].label,
              isUser: isUser,
            ),
            if (index < widget.message.imageAttachments.length - 1 ||
                text.trim().isNotEmpty)
              const SizedBox(height: 12),
          ],
          if (hasCodeFences)
            _MarkdownCodeMessage(
              text: text,
              textColor: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
              textTheme: textTheme,
              colorScheme: colorScheme,
            )
          else if (text.trim().isNotEmpty)
            SelectableText(
              text,
              maxLines: (isLongMessage && !_isExpanded) ? 15 : null,
              style: textTheme.bodyMedium?.copyWith(
                color: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
          if (isLongMessage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isExpanded ? 'Show less' : 'Show more',
                        style: textTheme.labelMedium?.copyWith(
                          color: isUser
                              ? colorScheme.onPrimary.withValues(alpha: 0.8)
                              : colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        _isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 16,
                        color: isUser
                            ? colorScheme.onPrimary.withValues(alpha: 0.8)
                            : colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!isUser &&
              widget.message.generationStats?.tokensPerSecond != null &&
              widget.message.generationStats?.elapsedMs != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _formatAssistantStats(widget.message),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!isUser && widget.message.toolActivity.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _MessageToolActivityList(
                activities: widget.message.toolActivity,
              ),
            ),
          if (!isUser && widget.message.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _MessageSources(sources: widget.message.sources),
            ),
          if (widget.onRegenerate != null ||
              widget.onReadAloud != null ||
              widget.extraActions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onReadAloud != null)
                    OutlinedButton.icon(
                      onPressed: widget.onReadAloud,
                      icon: Icon(
                        widget.isReading
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_outlined,
                        size: 16,
                      ),
                      label: Text(
                        widget.isReading ? 'Stop reading' : 'Read aloud',
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: actionForeground,
                        side: BorderSide(color: actionBorder),
                      ),
                    ),
                  // Pausing only exists while something is being read, so the
                  // row never offers a control that would do nothing.
                  if (widget.isReading && widget.onPauseReading != null)
                    OutlinedButton.icon(
                      onPressed: widget.onPauseReading,
                      icon: Icon(
                        widget.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_circle_outline,
                        size: 16,
                      ),
                      label: Text(widget.isPaused ? 'Resume' : 'Pause'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: actionForeground,
                        side: BorderSide(color: actionBorder),
                      ),
                    ),
                  if (widget.onRegenerate != null)
                    OutlinedButton.icon(
                      onPressed: widget.onRegenerate,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Regenerate'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: actionForeground,
                        side: BorderSide(color: actionBorder),
                      ),
                    ),
                  ...widget.extraActions,
                ],
              ),
            ),
          if (widget.below case final Widget below)
            Padding(padding: const EdgeInsets.only(top: 8), child: below),
        ],
      ),
    );

    if (hasExternalUserEdit) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Edit & Resend',
              onPressed: widget.onEditResend,
              icon: const Icon(Icons.edit_outlined),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(6),
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(child: bubble),
          ],
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }

  String _formatAssistantStats(Message message) {
    final stats = message.generationStats;
    final tps = stats?.tokensPerSecond ?? 0;
    final elapsedMs = stats?.elapsedMs ?? 0;
    final seconds = elapsedMs / 1000.0;
    final generatedTokens = stats?.generatedTokens;
    final promptTokens = stats?.promptTokens;
    final tokenPart = generatedTokens != null ? ' · $generatedTokens tok' : '';
    final promptPart = promptTokens != null ? ' · $promptTokens in' : '';
    return '${tps.toStringAsFixed(1)} tok/s · '
        '${seconds.toStringAsFixed(1)}s$tokenPart$promptPart';
  }
}

/// Tool calls an answer used: what ran on this device and what came back.
///
/// The record is stored with the message, so this reads the same after a
/// restart or an import on another device. Nothing here runs a tool; it only
/// reports what the registry already did.
class _MessageToolActivityList extends StatelessWidget {
  const _MessageToolActivityList({required this.activities});

  final List<MessageToolActivity> activities;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.build_outlined, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              activities.length == 1 ? 'Local tool' : 'Local tools',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final activity in activities)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.callLabel,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.status.label,
                      style: textTheme.labelSmall?.copyWith(
                        color: activity.isSuccess
                            ? colorScheme.primary
                            : colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (activity.output.trim().isNotEmpty)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            activity.output.trim(),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageSources extends ConsumerWidget {
  const _MessageSources({required this.sources});

  final List<MessageSource> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.folder_copy_outlined,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              sources.length == 1 ? 'Local source' : 'Local sources',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final source in sources)
              ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(source.citationLabel, style: textTheme.labelSmall),
                onPressed: () => _showSource(context, ref, source),
              ),
          ],
        ),
      ],
    );
  }

  void _showSource(BuildContext context, WidgetRef ref, MessageSource source) {
    final chunkText = _chunkTextFromCurrentIndex(ref, source);
    final terms = source.matchedTerms;
    final textTheme = Theme.of(context).textTheme;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(source.citationLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (terms.isNotEmpty) Text('Matched: ${terms.join(', ')}'),
            if (terms.isNotEmpty) const SizedBox(height: 12),
            Text(
              chunkText ??
                  'This document is no longer in the local index, or it was '
                      're-indexed since this answer. The citation above is '
                      'what the model was given.',
            ),
            const SizedBox(height: 12),
            Text(
              chunkText == null
                  ? 'Chunk ${source.chunkIndex + 1} is no longer stored.'
                  : 'Chunk ${source.chunkIndex + 1}, shown from the current '
                        'index — re-indexing the file can change it.',
              style: textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Chunk text from the index as it is now, or null when it is gone.
  static String? _chunkTextFromCurrentIndex(
    WidgetRef ref,
    MessageSource source,
  ) {
    final library = ref.read(documentsProvider.notifier).library;
    final document = library?.documentById(source.documentId);
    if (document == null) return null;
    for (final chunk in document.chunks) {
      if (chunk.index == source.chunkIndex) return chunk.text;
    }
    return null;
  }
}

class _MessageImage extends StatelessWidget {
  final String imagePath;
  final String? imageLabel;
  final bool isUser;

  const _MessageImage({
    required this.imagePath,
    required this.imageLabel,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageFile = File(imagePath);
    final imageExists = imageFile.existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 280),
            child: imageExists
                ? Image.file(imageFile, fit: BoxFit.cover)
                : Container(
                    width: 220,
                    height: 140,
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.12)
                        : colorScheme.surfaceContainerHigh,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 30,
                      color: isUser
                          ? colorScheme.onPrimary.withValues(alpha: 0.8)
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        if (imageLabel != null && imageLabel!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              imageLabel!,
              style: textTheme.labelSmall?.copyWith(
                color: isUser
                    ? colorScheme.onPrimary.withValues(alpha: 0.82)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _MarkdownCodeMessage extends StatelessWidget {
  final String text;
  final Color textColor;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  const _MarkdownCodeMessage({
    required this.text,
    required this.textColor,
    required this.textTheme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _parseSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isCode)
            _buildCodeBlock(context, segment)
          else if (segment.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                segment.text,
                style: textTheme.bodyMedium?.copyWith(color: textColor),
              ),
            ),
      ],
    );
  }

  Widget _buildCodeBlock(BuildContext context, _MarkdownSegment segment) {
    final codeBackground = colorScheme.surfaceContainerHigh;
    final languageLabel = segment.language?.isNotEmpty == true
        ? segment.language!
        : 'code';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    languageLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: segment.text));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code copied'),
                        duration: Duration(milliseconds: 900),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.content_copy_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              segment.text,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_MarkdownSegment> _parseSegments(String source) {
    final regex = RegExp(r'```([^\n`]*)\r?\n([\s\S]*?)```');
    final segments = <_MarkdownSegment>[];

    var cursor = 0;
    for (final match in regex.allMatches(source)) {
      if (match.start > cursor) {
        segments.add(
          _MarkdownSegment(text: source.substring(cursor, match.start)),
        );
      }
      segments.add(
        _MarkdownSegment(
          text: match.group(2) ?? '',
          isCode: true,
          language: (match.group(1) ?? '').trim(),
        ),
      );
      cursor = match.end;
    }

    if (cursor < source.length) {
      segments.add(_MarkdownSegment(text: source.substring(cursor)));
    }

    return segments;
  }
}

class _MarkdownSegment {
  final String text;
  final bool isCode;
  final String? language;

  const _MarkdownSegment({
    required this.text,
    this.isCode = false,
    this.language,
  });
}
