import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/github_star/star_prompt_store.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

final starPromptStoreProvider = FutureProvider<StarPromptStore>(
  (ref) => StarPromptStore.open(),
);

const githubRepoUrl = 'https://github.com/PradyX/instaLLM';

/// Whether the About row should carry a quiet dot: the reminder was shown but
/// never acted on.
final starPromptSeenProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(starPromptStoreProvider.future);
  final state = store.load();
  return state.hasBeenSeen && !state.optedOut;
});

enum StarPromptAnswer { notNow, starred }

/// How often the one-question reminder may appear.
const starPromptInterval = Duration(days: 14);
const starPromptMaxShows = 3;

class StarPromptController {
  StarPromptController(this._store);

  final StarPromptStore _store;

  /// The reminder only appears after a reply finished, at most once every two
  /// weeks and three times in total, and never again once it was acted on.
  bool get isDue {
    final state = _store.load();
    if (state.optedOut || state.shownCount >= starPromptMaxShows) return false;
    final last = state.lastShownAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= starPromptInterval;
  }

  bool get isReadOnly => _store.isReadOnly;

  bool get hasBeenSeen => _store.load().hasBeenSeen;

  void recordShown() {
    final state = _store.load();
    if (state.optedOut) return;
    final shown = state.shownCount + 1;
    _store.save(
      StarPromptState(
        shownCount: shown,
        lastShownAt: DateTime.now(),
        optedOut: shown >= starPromptMaxShows,
      ),
    );
  }

  void star() {
    final state = _store.load();
    _store.save(
      StarPromptState(
        shownCount: state.shownCount,
        lastShownAt: state.lastShownAt,
        optedOut: true,
      ),
    );
  }
}

/// Opens the repository in the user's browser; nothing is sent from the app.
Future<void> _openRepository() async {
  final uri = Uri.parse(githubRepoUrl);
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

/// The reminder dialog from mockup B: one question, two short lines, one action.
class StarPromptDialog extends StatelessWidget {
  const StarPromptDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.star.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.star.body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(StarPromptAnswer.notNow),
                    child: Text(t.star.notNow),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(StarPromptAnswer.starred),
                    child: Text(t.star.action),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks once per [starPromptInterval] after a reply finishes, and never blocks
/// the chat: dismissing it simply schedules the next check two weeks out.
Future<void> maybeShowStarPrompt(BuildContext context, WidgetRef ref) async {
  StarPromptController controller;
  try {
    controller = StarPromptController(
      await ref.read(starPromptStoreProvider.future),
    );
  } catch (_) {
    return;
  }
  if (controller.isReadOnly || !controller.isDue || !context.mounted) return;
  controller.recordShown();
  final answer = await showDialog<StarPromptAnswer>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const StarPromptDialog(),
  );
  if (answer == StarPromptAnswer.starred) {
    controller.star();
    await _openRepository();
  }
}

/// One quiet row for Settings → About, always available whether or not the
/// dialog has ever appeared.
class StarRepositoryTile extends StatelessWidget {
  const StarRepositoryTile({super.key, this.showDot = false});

  /// Marks the row until the dialog was answered, without interrupting anyone.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.star_outline_rounded),
      title: Text(t.star.settingsTitle),
      subtitle: Text(t.star.settingsSubtitle),
      trailing: showDot
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: () => unawaited(_openRepository()),
    );
  }
}
