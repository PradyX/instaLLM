import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/github_star/star_prompt.dart';
import 'package:installm/core/play_review/review_prompt.dart';

/// One gentle ask after a reply finishes: either the GitHub star question or
/// the Play Store rating sheet, never both.
///
/// Both nags share the same moment, so a single roll picks between them when
/// both happen to be due, and a reply that triggers neither stays untouched.
Future<void> maybeNudgeAfterReply(BuildContext context, WidgetRef ref) async {
  StarPromptController? star;
  ReviewPromptController? review;
  try {
    star = StarPromptController(await ref.read(starPromptStoreProvider.future));
    review = ReviewPromptController(
      await ref.read(reviewPromptStoreProvider.future),
    );
  } catch (_) {
    return;
  }

  // Both asks are random rather than scheduled: a finished reply only has a
  // small chance of raising one, so most chats end quietly.
  const chance = 0.35;
  final roll = Random();
  final starDue = !star.isReadOnly && star.isDue && roll.nextDouble() < chance;
  final reviewDue = !review.isReadOnly && review.isDue && review.rollSaysAsk;
  if (!starDue && !reviewDue) return;

  final showStar = starDue && (!reviewDue || roll.nextBool());
  if (showStar) {
    if (context.mounted) await maybeShowStarPrompt(context, ref);
  } else if (reviewDue) {
    await requestPlayReview(review);
  }
}
