import 'dart:io';

import 'package:pocket_llm/core/data/versioned_json_document.dart';
import 'package:pocket_llm/features/profile_images/domain/petdex_pet.dart';

/// Cosmetic overrides also cover built-in bots without modifying templates.
/// Version 1 is additive: existing bot/room documents are left untouched.
class ProfileImageStore {
  ProfileImageStore(File file)
    : _document = VersionedJsonDocument(
        file: file,
        currentVersion: 1,
        label: 'ProfileImageStore',
        isPayloadUsable: (json) => json['selections'] is Map,
      );

  final VersionedJsonDocument _document;
  bool get isReadOnly => _document.isReadOnly;

  Map<String, PetdexPet> load() {
    final raw = _document.read()?['selections'];
    if (raw is! Map) return {};
    final selections = <String, PetdexPet>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final pet = PetdexPet.fromJson(entry.value);
      if (key is String &&
          (key.startsWith('bot:') || key.startsWith('room:')) &&
          pet != null) {
        selections[key] = pet;
      }
    }
    return selections;
  }

  bool save(Map<String, PetdexPet> selections) => _document.write({
    'version': 1,
    'selections': selections.map((key, pet) => MapEntry(key, pet.toJson())),
  });
}
