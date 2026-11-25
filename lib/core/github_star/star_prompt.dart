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
const sponsorUrl = 'https://github.com/sponsors/PradyX';

/// Whether the About row should carry a quiet dot: the reminder was shown but
/// never acted on.
final starPromptSeenProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(starPromptStoreProvider.future);
  final state = store.load();
  return state.hasBeenSeen && !state.optedOut;
});

enum StarPromptAnswer { notNow, starred }

class StarPromptController {
  StarPromptController(this._store);

  final StarPromptStore _store;

  /// The one-question reminder is offered until it was answered once. It never
  /// repeats, so nobody reads the same ask in every session.
  bool get isDue => !_store.load().optedOut;

  bool get isReadOnly => _store.isReadOnly;

  bool get hasBeenSeen => _store.load().hasBeenSeen;

  /// Records that the dialog was put in front of the user, which only feeds the
  /// quiet dot on the Settings row.
  void recordShown() {
    final state = _store.load();
    if (state.optedOut) return;
    _store.save(
      StarPromptState(
        shownCount: state.shownCount + 1,
        lastShownAt: DateTime.now(),
      ),
    );
  }

  /// Any answer ends it for good. Dismissing is an answer too: asking the same
  /// question twice is what makes a reminder feel like nagging.
  void recordAnswer() {
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
Future<void> openGitHubRepository() => _openInBrowser(githubRepoUrl);

/// Opens the sponsor page, the second of the sidebar's two community actions.
Future<void> openSponsorPage() => _openInBrowser(sponsorUrl);

Future<void> _openInBrowser(String url) async {
  final uri = Uri.parse(url);
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
  // A tap outside or the back gesture is a dismissal, not a deferral: every
  // answer, including "No thanks", silences the reminder from now on.
  controller.recordAnswer();
  if (answer == StarPromptAnswer.starred) await openGitHubRepository();
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
      onTap: () => unawaited(openGitHubRepository()),
    );
  }
}
