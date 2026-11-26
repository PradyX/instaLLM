import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/core/widgets/llm_chip_icon.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';
import 'package:installm/features/model_selection/presentation/model_reasoning_provider.dart';

/// Key for the composer's model menu, so a test can prove one tap opens both
/// selectors.
const Key composerModelMenuKey = ValueKey('composer-model-menu');

/// The composer's model control: one pill that names the model in use and
/// whether it thinks before answering, and one menu behind it that carries both
/// choices.
///
/// Home (the conversation's model) and a bot's room (that room's model) both
/// hang it off [ChatComposer.leading], so the two controls cannot drift into
/// different shapes or menus. It is also what makes the choice discoverable:
/// the pill names the model in use instead of hiding the setting in a settings
/// page.
///
/// One pill rather than two chips is what a phone width allows: two chips plus
/// the attach and send buttons did not fit on a 393 dp screen. The reasoning
/// state rides in the same line as `· off`, and the two selectors live in one
/// menu instead of two, so a tap opens everything the pill summarises.
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
    this.maxWidth = 160,
    this.reasoning,
    this.reasoningChoice,
    this.onReasoningSelected,
    this.menuWidth = 300,
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

  /// Keeps a long model name from crowding the state label beside it.
  final double maxWidth;

  /// What the model declares about thinking, or null for a model whose chat
  /// template declares nothing: no state label, no row in the menu.
  final ModelReasoning? reasoning;

  /// The state in force — the user's pick, or the model's own default.
  final ReasoningChoice? reasoningChoice;

  /// Called with the state the user picked, never with one the model does not
  /// declare.
  final ValueChanged<ReasoningChoice>? onReasoningSelected;

  /// Width of the menu card; the height follows the model count up to a cap.
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    final model = selected;
    if (model == null) {
      return TextButton(onPressed: onEmptyPressed, child: Text(emptyLabel));
    }
    return _ComposerPill(
      models: models,
      model: model,
      enabled: enabled,
      onSelected: onSelected,
      tooltip: tooltip,
      maxWidth: maxWidth,
      reasoning: reasoning,
      choice: reasoningChoice,
      onReasoningSelected: onReasoningSelected,
      menuWidth: menuWidth,
    );
  }
}

/// The pill, and the menu it opens above itself.
///
/// The menu is an overlay rather than a route so the composer stays visible and
/// the panel reads as attached to the pill; it is placed from the pill's own
/// rectangle, clamped to the screen, and closed by picking a model or tapping
/// anywhere off it.
class _ComposerPill extends StatefulWidget {
  const _ComposerPill({
    required this.models,
    required this.model,
    required this.enabled,
    required this.onSelected,
    required this.tooltip,
    required this.maxWidth,
    required this.reasoning,
    required this.choice,
    required this.onReasoningSelected,
    required this.menuWidth,
  });

  final List<LlmModel> models;
  final LlmModel model;
  final bool enabled;
  final ValueChanged<LlmModel>? onSelected;
  final String tooltip;
  final double maxWidth;
  final ModelReasoning? reasoning;
  final ReasoningChoice? choice;
  final ValueChanged<ReasoningChoice>? onReasoningSelected;
  final double menuWidth;

  @override
  State<_ComposerPill> createState() => _ComposerPillState();
}

class _ComposerPillState extends State<_ComposerPill> {
  OverlayEntry? _menu;

  @override
  void dispose() {
    _menu?.remove();
    _menu = null;
    super.dispose();
  }

  void _toggle() {
    if (_menu == null) {
      _open();
    } else {
      _close();
    }
  }

  void _close() {
    _menu?.remove();
    _menu = null;
  }

  void _open() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final pill = box.localToGlobal(Offset.zero) & box.size;

    final media = MediaQuery.sizeOf(context);
    final inset = 16.0;
    final width = math.min(widget.menuWidth, media.width - inset * 2);
    final left = pill.left
        .clamp(inset, math.max(inset, media.width - width - inset))
        .toDouble();
    final maxHeight = math.min(360.0, media.height * 0.55);
    // Above the pill when there is room, which is the usual case: the composer
    // sits at the bottom of the screen, so a menu under it would be pushed off
    // the edge. A pill near the top (a room's toolbar, a very short window)
    // opens downwards instead of drawing itself off screen.
    const gap = 8.0;
    final spaceAbove = pill.top - inset;
    final spaceBelow = media.height - pill.bottom - inset;
    final openAbove = spaceAbove >= maxHeight || spaceAbove >= spaceBelow;

    final reasoning = widget.reasoning;
    var choice = widget.choice;
    final onReasoning = widget.onReasoningSelected;

    _menu = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          // The barrier is the whole screen, so a tap anywhere else closes the
          // menu the way a popup menu does.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: openAbove ? null : pill.bottom + gap,
            bottom: openAbove ? media.height - pill.top + gap : null,
            width: width,
            child: _ComposerMenuCard(
              models: widget.models,
              selectedId: widget.model.id,
              reasoning: reasoning,
              choice: choice,
              maxHeight: maxHeight,
              onPicked: (model) {
                _close();
                widget.onSelected?.call(model);
              },
              onReasoningPicked: reasoning == null || onReasoning == null
                  ? null
                  : (picked) {
                      choice = picked;
                      onReasoning(picked);
                      // The pill behind the menu keeps the new state; the
                      // menu's own segment has to redraw for the same reason.
                      _menu?.markNeedsBuild();
                    },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_menu!);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final choice = widget.choice;

    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            onTap: widget.enabled ? _toggle : null,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LlmChipIcon(size: 16, color: colorScheme.primary),
                  const SizedBox(width: 7),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.maxWidth),
                      child: Text(
                        '${widget.model.name} · ${widget.model.parameterSize}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // The state, not a second control: "· off" is the shortest
                  // honest way to say it, and it is what lets the model name
                  // keep its width on a 360 dp row.
                  if (choice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${choice.id}',
                      maxLines: 1,
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The menu: the models, then — under one divider — the thinking state for the
/// model in use. One card, because both answer the same question: what runs
/// this reply and how.
class _ComposerMenuCard extends StatelessWidget {
  const _ComposerMenuCard({
    required this.models,
    required this.selectedId,
    required this.reasoning,
    required this.choice,
    required this.maxHeight,
    required this.onPicked,
    required this.onReasoningPicked,
  });

  final List<LlmModel> models;
  final String selectedId;
  final ModelReasoning? reasoning;
  final ReasoningChoice? choice;
  final double maxHeight;
  final ValueChanged<LlmModel> onPicked;
  final ValueChanged<ReasoningChoice>? onReasoningPicked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reasoning = this.reasoning;
    final choice = this.choice;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        key: composerModelMenuKey,
        color: colorScheme.surfaceContainerHigh,
        elevation: 8,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Text(
                        'MODEL',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    for (final model in models)
                      _ModelRow(
                        model: model,
                        selected: model.id == selectedId,
                        onTap: () => onPicked(model),
                      ),
                  ],
                ),
              ),
              if (reasoning != null && choice != null) ...[
                Divider(
                  height: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                ),
                _ThinkingRow(
                  reasoning: reasoning,
                  choice: choice,
                  onSelected: onReasoningPicked,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final LlmModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      key: ValueKey('composer-model-${model.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                model.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              model.parameterSize,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The menu's foot: the thinking state as two segments, so the choice is one
/// tap and its current value is visible without opening anything else.
class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow({
    required this.reasoning,
    required this.choice,
    required this.onSelected,
  });

  final ModelReasoning reasoning;
  final ReasoningChoice choice;
  final ValueChanged<ReasoningChoice>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
      child: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          // The label takes whatever the segments leave, so the control sits
          // against the card's right edge where a segmented control belongs and
          // the label gives way first: a clipped "Thinki…" still says which
          // setting the row is, a clipped state name does not.
          Expanded(
            child: Text(
              'Thinking',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Both segments must stay whole; where a large text size would not fit,
          // the control scales down rather than clipping a state's name.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Off first: the quiet state is the one most replies want,
                    // and a control should open on the choice that costs least.
                    for (final option
                        in reasoning.choices.toList()..sort(
                          (a, b) => (a == ReasoningChoice.thinkingOff ? 0 : 1)
                              .compareTo(
                                b == ReasoningChoice.thinkingOff ? 0 : 1,
                              ),
                        ))
                      _ThinkingSegment(
                        option: option,
                        selected: option == choice,
                        enabled: onSelected != null,
                        onTap: () => onSelected?.call(option),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingSegment extends StatelessWidget {
  const _ThinkingSegment({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ReasoningChoice option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('composer-reasoning-${option.id}'),
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          option.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The pill with its values read from the app: the reasoning a model declares
/// lives in its installed file, and the choice the user made lives in settings,
/// so a caller cannot show a control the model does not have.
class ComposerModelControl extends ConsumerWidget {
  const ComposerModelControl({
    super.key,
    required this.models,
    required this.selected,
    required this.enabled,
    this.onSelected,
    this.tooltip = 'Switch model',
    this.emptyLabel = 'Get a model',
    this.onEmptyPressed,
  });

  final List<LlmModel> models;
  final LlmModel? selected;
  final bool enabled;
  final ValueChanged<LlmModel>? onSelected;
  final String tooltip;
  final String emptyLabel;
  final VoidCallback? onEmptyPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelId = selected?.id ?? '';
    final reasoning = modelId.isEmpty
        ? null
        : ref.watch(modelReasoningProvider(modelId)).value;
    final choice = reasoning == null
        ? null
        : ref.watch(reasoningSettingsProvider).choiceFor(modelId) ??
              reasoning.defaultChoice;

    return ComposerModelPill(
      models: models,
      selected: selected,
      enabled: enabled,
      onSelected: onSelected,
      tooltip: tooltip,
      emptyLabel: emptyLabel,
      onEmptyPressed: onEmptyPressed,
      reasoning: reasoning,
      reasoningChoice: choice,
      onReasoningSelected: reasoning == null
          ? null
          : (next) => unawaited(
              ref
                  .read(reasoningSettingsProvider.notifier)
                  .setChoice(modelId, next),
            ),
    );
  }
}
