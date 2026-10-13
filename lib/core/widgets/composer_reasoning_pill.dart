import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';
import 'package:installm/features/model_selection/presentation/model_reasoning_provider.dart';

/// The composer's reasoning chip: whether the model deliberates before it
/// answers, drawn beside the model pill.
///
/// The chip exists only for models whose own chat template declares the choice
/// (see [ModelReasoning]); the wrapper reads that from the installed file, so a
/// caller cannot show a control the model does not have. It shows the state in
/// force — the user's pick, or the model's own default until they make one —
/// and its menu lists the states the model declares, with the model's default
/// marked as such.
class ComposerReasoningControl extends ConsumerWidget {
  const ComposerReasoningControl({
    super.key,
    required this.modelId,
    required this.enabled,
  });

  /// The model whose reasoning is being chosen; empty when there is none yet.
  final String modelId;

  /// False while a run is in flight: the chip stays readable but closed.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (modelId.isEmpty) return const SizedBox.shrink();

    final reasoning = ref.watch(modelReasoningProvider(modelId)).valueOrNull;
    if (reasoning == null) return const SizedBox.shrink();

    final choice =
        ref.watch(reasoningSettingsProvider).choiceFor(modelId) ??
        reasoning.defaultChoice;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ComposerReasoningPill(
        reasoning: reasoning,
        choice: choice,
        enabled: enabled,
        onSelected: (next) => unawaited(
          ref.read(reasoningSettingsProvider.notifier).setChoice(modelId, next),
        ),
      ),
    );
  }
}

/// The chip itself, with no opinion about where its values come from.
class ComposerReasoningPill extends StatelessWidget {
  const ComposerReasoningPill({
    super.key,
    required this.reasoning,
    required this.choice,
    required this.enabled,
    this.onSelected,
    this.tooltip = 'Reasoning',
  });

  /// What the model declares: which states exist and which one it starts in.
  final ModelReasoning reasoning;

  /// The state in force.
  final ReasoningChoice choice;

  final bool enabled;

  /// Called with the state the user picked, never with one the model does not
  /// declare.
  final ValueChanged<ReasoningChoice>? onSelected;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReasoningChoice>(
      tooltip: tooltip,
      enabled: enabled,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final candidate in reasoning.choices)
          CheckedPopupMenuItem<ReasoningChoice>(
            value: candidate,
            checked: candidate == choice,
            child: Row(
              children: [
                Flexible(
                  child: Text(candidate.label, overflow: TextOverflow.ellipsis),
                ),
                // The model's own default is worth naming: it is the state a
                // fresh install runs in, and the one to return to.
                if (candidate == reasoning.defaultChoice) ...[
                  const SizedBox(width: 8),
                  const _DefaultBadge(),
                ],
              ],
            ),
          ),
      ],
      child: _ChipBody(choice: choice),
    );
  }
}

/// The chip: same shape as the model pill, so the two read as one row of
/// settings rather than two kinds of control.
class _ChipBody extends StatelessWidget {
  const _ChipBody({required this.choice});

  final ReasoningChoice choice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // One icon for the setting, not for its value: the label already
          // says which state is in force.
          Icon(Icons.psychology_outlined, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            choice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.expand_more_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Default',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
