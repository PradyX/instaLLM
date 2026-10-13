import 'package:flutter/material.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// The composer's model pill: which model the next answer runs on, tapped to
/// switch it.
///
/// Home (the conversation's model) and a bot's room (that room's model) both
/// hang it off [ChatComposer.leading], so the two controls cannot drift into
/// different shapes or menus. It is also what makes the choice discoverable:
/// the pill names the model in use instead of hiding the setting in a
/// settings page.
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

  /// Keeps a long model name from crowding the mic and send buttons.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final model = selected;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: model == null
          ? TextButton(onPressed: onEmptyPressed, child: Text(emptyLabel))
          : PopupMenuButton<String>(
              tooltip: tooltip,
              enabled: enabled,
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
              child: _PillBody(model: model),
            ),
    );
  }
}

/// The pill itself: a memory chip above the field's action row.
class _PillBody extends StatelessWidget {
  const _PillBody({required this.model});

  final LlmModel model;

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
          Icon(Icons.memory_outlined, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${model.name} · ${model.parameterSize}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
