import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocket_llm/core/data/versioned_json_document.dart';
import 'package:pocket_llm/core/theme/appearance_preferences.dart';

class AppearanceStore {
  AppearanceStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: 2,
        label: 'AppearanceStore',
        isPayloadUsable: (json) =>
            json['surfaceStyle'] is String ||
            json['accent'] is String ||
            (json['contrast'] is num && (json['contrast'] as num).isFinite) ||
            (json['glassOpacity'] is num &&
                (json['glassOpacity'] as num).isFinite),
      );

  final VersionedJsonDocument _document;
  bool get isReadOnly => _document.isReadOnly;

  static Future<AppearanceStore> open() async {
    final directory = await getApplicationSupportDirectory();
    return AppearanceStore(
      File(p.join(directory.path, 'appearance', 'preferences.json')),
    );
  }

  AppearancePreferences load() =>
      AppearancePreferences.fromJson(_document.read() ?? {});

  bool save(AppearancePreferences preferences) =>
      _document.write({'version': 2, ...preferences.toJson()});
}
