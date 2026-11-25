import 'dart:io';

import 'package:installm/core/data/versioned_json_document.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// What the Play update prompt remembers between launches.
///
/// It is only a quiet period, so it lives in its own small versioned file
/// beside the star and review prompts instead of touching settings.
class UpdatePromptState {
  const UpdatePromptState({this.dismissedAt, this.dismissedVersionCode});

  /// When the prompt was last dismissed, or null if it never was.
  final DateTime? dismissedAt;

  /// The Play version code the user dismissed. A different build asks again
  /// straight away, because it is a different update and worth mentioning.
  final int? dismissedVersionCode;

  Map<String, dynamic> toJson() => {
    'dismissedAt': dismissedAt?.toIso8601String(),
    'dismissedVersionCode': dismissedVersionCode,
  };

  factory UpdatePromptState.fromJson(Map<String, dynamic> json) {
    final at = json['dismissedAt'];
    final code = json['dismissedVersionCode'];
    return UpdatePromptState(
      dismissedAt: at is String ? DateTime.tryParse(at) : null,
      dismissedVersionCode: code is int ? code : null,
    );
  }
}

class UpdatePromptStore {
  UpdatePromptStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: 1,
        label: 'UpdatePromptStore',
        isPayloadUsable: (json) =>
            json['dismissedAt'] == null || json['dismissedAt'] is String,
      );

  final VersionedJsonDocument _document;

  /// Reads first: the document only knows it belongs to a newer build once it
  /// has seen the file, and the caller checks this before showing anything.
  bool get isReadOnly {
    _document.read();
    return _document.isReadOnly;
  }

  static Future<UpdatePromptStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return UpdatePromptStore(
      File(p.join(directory.path, 'play_update', 'state.json')),
    );
  }

  UpdatePromptState load() =>
      UpdatePromptState.fromJson(_document.read() ?? const {});

  bool save(UpdatePromptState state) {
    // The read marks a newer-build file read-only, which makes the write below
    // refuse instead of overwriting a schema this build does not understand.
    _document.read();
    return _document.write({'version': 1, ...state.toJson()});
  }
}
