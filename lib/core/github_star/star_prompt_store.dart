import 'dart:io';

import 'package:installm/core/data/versioned_json_document.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What the GitHub star reminder remembers between launches.
///
/// It is cosmetic state, so it lives in its own small versioned file next to the
/// appearance preferences instead of touching conversations or settings.
class StarPromptState {
  const StarPromptState({
    this.shownCount = 0,
    this.lastShownAt,
    this.optedOut = false,
  });

  final int shownCount;
  final DateTime? lastShownAt;

  /// True once the user answered the reminder in any way — starring the
  /// repository or dismissing it — so it never comes back.
  final bool optedOut;

  bool get hasBeenSeen => shownCount > 0;

  Map<String, dynamic> toJson() => {
    'shownCount': shownCount,
    'lastShownAt': lastShownAt?.toIso8601String(),
    'optedOut': optedOut,
  };

  factory StarPromptState.fromJson(Map<String, dynamic> json) {
    final count = json['shownCount'];
    final shown = json['lastShownAt'];
    return StarPromptState(
      shownCount: count is int && count >= 0 ? count : 0,
      lastShownAt: shown is String ? DateTime.tryParse(shown) : null,
      optedOut: json['optedOut'] == true,
    );
  }
}

class StarPromptStore {
  StarPromptStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: 1,
        label: 'StarPromptStore',
        isPayloadUsable: (json) => json['shownCount'] is int,
      );

  final VersionedJsonDocument _document;

  bool get isReadOnly => _document.isReadOnly;

  static Future<StarPromptStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return StarPromptStore(
      File(p.join(directory.path, 'star_prompt', 'state.json')),
    );
  }

  StarPromptState load() =>
      StarPromptState.fromJson(_document.read() ?? const {});

  bool save(StarPromptState state) =>
      _document.write({'version': 1, ...state.toJson()});
}
