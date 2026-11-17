import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:installm/core/data/versioned_json_document.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final reviewPromptStoreProvider = FutureProvider<ReviewPromptStore>(
  (ref) => ReviewPromptStore.open(),
);

/// What the Play Store rating nudge remembers between launches.
///
/// Play enforces its own quota on the in-app review sheet, so this file only
/// keeps the app from asking more often than the quota allows.
class ReviewPromptState {
  const ReviewPromptState({this.requestedCount = 0, this.lastRequestedAt});

  final int requestedCount;
  final DateTime? lastRequestedAt;

  Map<String, dynamic> toJson() => {
    'requestedCount': requestedCount,
    'lastRequestedAt': lastRequestedAt?.toIso8601String(),
  };

  factory ReviewPromptState.fromJson(Map<String, dynamic> json) {
    final count = json['requestedCount'];
    final last = json['lastRequestedAt'];
    return ReviewPromptState(
      requestedCount: count is int && count >= 0 ? count : 0,
      lastRequestedAt: last is String ? DateTime.tryParse(last) : null,
    );
  }
}

class ReviewPromptStore {
  ReviewPromptStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: 1,
        label: 'ReviewPromptStore',
        isPayloadUsable: (json) => json['requestedCount'] is int,
      );

  final VersionedJsonDocument _document;

  bool get isReadOnly => _document.isReadOnly;

  static Future<ReviewPromptStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return ReviewPromptStore(
      File(p.join(directory.path, 'play_review', 'state.json')),
    );
  }

  ReviewPromptState load() =>
      ReviewPromptState.fromJson(_document.read() ?? const {});

  bool save(ReviewPromptState state) =>
      _document.write({'version': 1, ...state.toJson()});
}

/// The rating nudge is rarer than the star one: Play's own sheet is the only
/// thing it shows, its quota is small, and interrupting a chat is worse than
/// missing the ask.
const reviewPromptInterval = Duration(days: 120);
const reviewPromptMaxRequests = 2;
const reviewPromptChance = 0.35;

class ReviewPromptController {
  ReviewPromptController(this._store, {Random? random})
    : _random = random ?? Random();

  final ReviewPromptStore _store;
  final Random _random;

  bool get isReadOnly => _store.isReadOnly;

  bool get isDue {
    final state = _store.load();
    if (state.requestedCount >= reviewPromptMaxRequests) return false;
    final last = state.lastRequestedAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= reviewPromptInterval;
  }

  /// Even when due, most finished replies pass without asking: the rating
  /// sheet should feel random rather than scheduled.
  bool get rollSaysAsk => _random.nextDouble() < reviewPromptChance;

  void recordAsked() {
    final state = _store.load();
    _store.save(
      ReviewPromptState(
        requestedCount: state.requestedCount + 1,
        lastRequestedAt: DateTime.now(),
      ),
    );
  }
}

const playStoreId = 'com.prady.installm';
const playStoreUrl =
    'https://play.google.com/store/apps/details?id=$playStoreId';

/// Opens the listing rather than the review sheet: the sheet is quota limited
/// and cannot be called from a button, but the listing always opens.
Future<void> openPlayStoreListing() async {
  if (Platform.isAndroid) {
    try {
      await InAppReview.instance.openStoreListing(appStoreId: playStoreId);
      return;
    } catch (_) {
      // Fall through to the web listing on a device without the Play Store.
    }
  }
  final uri = Uri.parse(playStoreUrl);
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

/// The quiet row beside the GitHub one: no dot, no interruption.
class RatePlayStoreTile extends StatelessWidget {
  const RatePlayStoreTile({super.key});

  @override
  Widget build(BuildContext context) {
    // Play is Android-only; the row would be a dead link on macOS and Linux.
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.rate_review_outlined),
      title: Text(t.star.rateTitle),
      subtitle: Text(t.star.rateSubtitle),
      onTap: openPlayStoreListing,
    );
  }
}

/// Asks Play for its native review sheet. It is a no-op off Android and on
/// builds Play does not serve, so desktop runs never see it.
Future<void> requestPlayReview(ReviewPromptController controller) async {
  if (!Platform.isAndroid) return;
  try {
    final review = InAppReview.instance;
    if (!await review.isAvailable()) return;
    controller.recordAsked();
    await review.requestReview();
  } catch (_) {
    // A missing Play Store, a sideloaded build or an exhausted quota all fail
    // here; none of them is worth showing the user an error for.
  }
}
