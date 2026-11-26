import 'package:flutter/material.dart';
import 'package:installm/core/widgets/llm_chip_icon.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// The composer's model pill: which model the next answer runs on, tapped to
/// switch it, with the model's own reasoning choice drawn inside the same pill
/// after a divider.
///
/// Home (the conversation's model) and a bot's room (that room's model) both
/// hang it off [ChatComposer.leading], so the two controls cannot drift into
/// different shapes or menus. It is also what makes the choice discoverable:
/// the pill names the model in use instead of hiding the setting in a
/// settings page.
///
/// One pill rather than two is what a phone width allows: two chips plus the
/// attach and send buttons did not fit on a 393 dp screen, so the second chip
/// squeezed the buttons off the edge. [reasoning] is a second menu inside the
/// same surface, separated by a 1 px divider.
class ComposerModelPill extends StatelessWidget {
  const ComposerModelPill({
    super.key,
    required this.models,
    required this.selected,
    required this.enabled,
    this.onSelected,
    this.tooltip = 'Switch model',
    this.emptyLabel = 'Get a model',
    this.onEmptyPressed,
    this.maxWidth = 190,
    this.reasoning,
  });

  /// The models the menu offers, in order. The same list the answer would
  /// resolve from — a pill that could offer an unusable model would lie.
  final List<LlmModel> models;

  /// The model in use, or null with nothing to offer: the pill becomes
  /// [emptyLabel] instead, which is where a user without a model is told so.
  final LlmModel? selected;

  /// False while a run is in flight: the pill stays readable but closed.
  final bool enabled;

  /// Called with the model the user picked, never with an id that is not in
  /// [models].
  final ValueChanged<LlmModel>? onSelected;

  final String tooltip;

  /// Shown in place of the pill when there is no model to choose from.
  final String emptyLabel;

  /// Where [emptyLabel] leads — the model library, on every surface.
  final VoidCallback? onEmptyPressed;

  /// Keeps a long model name from crowding the rest of the row.
  final double maxWidth;

  /// The second selector inside the pill, drawn to the right of the divider it
  /// brings with it. It draws nothing at all for a model that declares no
  /// reasoning, and the divider goes with it, so the pill never ends in a lone
  /// rule.
  final Widget? reasoning;

  @override
  Widget build(BuildContext context) {
    final model = selected;
    if (model == null) {
      return TextButton(onPressed: onEmptyPressed, child: Text(emptyLabel));
    }
    final colorScheme = Theme.of(context).colorScheme;
    final trailing = reasoning;
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
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: tooltip,
              enabled: enabled,
              padding: EdgeInsets.zero,
              onSelected: (modelId) {
                for (final candidate in models) {
                  if (candidate.id == modelId) {
                    onSelected?.call(candidate);
                    return;
                  }
                }
              },
              // Only models: a room's pick is a model, and nothing in the menu
              // pretends to be one.
              itemBuilder: (context) => [
                for (final candidate in models)
                  CheckedPopupMenuItem<String>(
                    value: candidate.id,
                    checked: candidate.id == model.id,
                    child: Text(
                      '${candidate.name} · ${candidate.parameterSize}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              child: _ModelSegment(model: model, maxWidth: maxWidth),
            ),
          ),
          // The reasoning selector keeps its own width; the model name is the
          // part that gives way, because a truncated name is still readable and
          // a truncated state label is not.
          ?trailing,
        ],
      ),
    );
  }
}

/// The pill's first half: the model in use, and a chevron saying it opens.
class _ModelSegment extends StatelessWidget {
  const _ModelSegment({required this.model, required this.maxWidth});

  final LlmModel model;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LlmChipIcon(size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Text(
              '${model.name} · ${model.parameterSize}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Icon(
          Icons.expand_more_rounded,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
