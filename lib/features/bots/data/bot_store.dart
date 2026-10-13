import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/core/data/versioned_json_document.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';

/// User-created bots. Templates are offered separately, never seeded on load.
class BotStore {
  BotStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: currentVersion,
        label: 'BotStore',
      );

  static const int currentVersion = 2;

  static Future<BotStore> open() async {
    final support = await getApplicationSupportDirectory();
    return BotStore(File(p.join(support.path, 'bots', 'bots.json')));
  }

  final VersionedJsonDocument _document;
  bool _needsLegacyBackup = false;
  bool _needsPartialBackup = false;

  String get filePath => _document.filePath;
  bool get isReadOnly => _document.isReadOnly;

  BotsSnapshot load() {
    final decoded = _document.read();
    if (decoded == null) return BotsSnapshot.empty;
    _needsLegacyBackup = decoded['version'] != currentVersion;
    final snapshot = BotsSnapshot.fromJson(decoded);
    final raw = decoded['bots'];
    _needsPartialBackup =
        raw is! List || raw.length != snapshot.customBots.length;
    return snapshot;
  }

  bool save(BotsSnapshot snapshot) {
    // Keep the entire legacy payload, including partial/invalid entries,
    // before writing the registry that no longer adds templates on load.
    if (_needsLegacyBackup || _needsPartialBackup) {
      try {
        _document.file.copySync(
          '$filePath.${_needsLegacyBackup ? 'v1' : 'partial'}-${DateTime.now().microsecondsSinceEpoch}',
        );
        _needsLegacyBackup = false;
        _needsPartialBackup = false;
      } catch (_) {
        return false;
      }
    }
    return _document.write({
      'version': currentVersion,
      'bots': snapshot.customBots.map((bot) => bot.toJson()).toList(),
    });
  }
}

class BotsSnapshot {
  const BotsSnapshot({required this.customBots});

  static const BotsSnapshot empty = BotsSnapshot(customBots: []);

  final List<Bot> customBots;

  List<Bot> get allBots => customBots;

  BotsSnapshot upsert(Bot bot) {
    final updated = <Bot>[];
    var replaced = false;
    for (final existing in customBots) {
      if (existing.id == bot.id) {
        updated.add(bot);
        replaced = true;
      } else {
        updated.add(existing);
      }
    }
    if (!replaced) updated.add(bot);
    return BotsSnapshot(customBots: updated);
  }

  BotsSnapshot remove(String botId) {
    return BotsSnapshot(
      customBots: customBots.where((bot) => bot.id != botId).toList(),
    );
  }

  static BotsSnapshot fromJson(Map<String, dynamic> json) {
    final raw = json['bots'];
    final bots = <Bot>[];
    if (raw is List) {
      for (final entry in raw) {
        final map = entry is Map<String, dynamic>
            ? entry
            : entry is Map && entry.keys.every((key) => key is String)
            ? Map<String, dynamic>.from(entry)
            : null;
        if (map == null) continue;
        // Version 1 never owned these records: keep its template-shadowing
        // rule. Version 2 treats every saved record as a user-created bot.
        final id = map['id'];
        if (id is! String) continue;
        if (json['version'] != BotStore.currentVersion &&
            BuiltInBots.byId(id) != null) {
          continue;
        }
        final bot = Bot.fromJson(map);
        if (bot != null && !bots.any((existing) => existing.id == bot.id)) {
          bots.add(bot);
        }
      }
    }
    return BotsSnapshot(customBots: bots);
  }
}
