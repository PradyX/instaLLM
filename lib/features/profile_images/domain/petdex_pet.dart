/// Public Petdex metadata. Never carries bot names, prompts or room content.
class PetdexPet {
  const PetdexPet({
    required this.slug,
    required this.name,
    required this.spritesheetUrl,
    this.creator = '',
  });

  final String slug;
  final String name;
  final String creator;
  final String spritesheetUrl;

  String get previewUrl => 'https://assets.petdex.dev/pets/$slug/preview.webp';

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'displayName': name,
    'submittedBy': creator,
    'spritesheetUrl': spritesheetUrl,
  };

  static PetdexPet? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'];
    final name = raw['displayName'];
    final sprite = raw['spritesheetUrl'];
    if (slug is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9-]{0,159}$').hasMatch(slug) ||
        name is! String ||
        name.trim().isEmpty ||
        sprite is! String ||
        !isAssetUrl(sprite)) {
      return null;
    }
    return PetdexPet(
      slug: slug,
      name: name,
      spritesheetUrl: sprite,
      creator: raw['submittedBy'] is String ? raw['submittedBy'] as String : '',
    );
  }

  static bool isAssetUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'assets.petdex.dev' &&
        uri.userInfo.isEmpty &&
        !uri.hasPort;
  }

  @override
  bool operator ==(Object other) =>
      other is PetdexPet &&
      other.slug == slug &&
      other.spritesheetUrl == spritesheetUrl;

  @override
  int get hashCode => Object.hash(slug, spritesheetUrl);
}

String botProfileKey(String botId) => 'bot:$botId';
String roomProfileKey(String roomId) => 'room:$roomId';
