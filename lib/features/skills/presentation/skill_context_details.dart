import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/skills/application/skill_usage.dart';
import 'package:installm/i18n/strings.g.dart';

/// Quiet, shared entry to the last request's context estimates. No private
/// instruction/resource text is retained or rendered by this inspector.
class SkillContextDetails extends ConsumerWidget {
  const SkillContextDetails({super.key, required this.sessionKey, this.child});
  final String sessionKey;
  final Widget? child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(skillUsageProvider)[sessionKey];
    if (usage == null || usage.skills == 0) {
      return child ?? const SizedBox.shrink();
    }
    void open() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.skills.lastRequest,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final row in [
                  (t.skills.bodyTokens, usage.instructions),
                  (t.skills.resourceTokens, usage.resources),
                  (t.skills.observationTokens, usage.scriptResults),
                  (t.skills.otherInput, usage.otherInput),
                  (t.skills.inputTotal, usage.inputTokens),
                  (t.skills.outputReservation, usage.reservedOutput),
                  (t.skills.window, usage.window),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(child: Text(row.$1)),
                        const SizedBox(width: 12),
                        Text('${row.$2}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (child != null) {
      return Tooltip(
        message: t.skills.inspector,
        child: Semantics(
          button: true,
          label: t.skills.inspector,
          child: InkWell(onTap: open, child: child),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: open,
        child: Text(
          '${t.skills.title}: ${usage.skills} · ${t.skills.inspector}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
