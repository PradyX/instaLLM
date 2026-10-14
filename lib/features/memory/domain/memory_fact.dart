enum MemoryScope { conversation, workspace, global }

enum MemorySource { userStated, inferred, botRecorded }

/// A taught fact, separate from automatic conversation summaries.
class MemoryFact {
  MemoryFact({
    required this.id,
    required this.scope,
    required this.text,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.ownerId,
    this.expiresAt,
    this.globalOptIn = false,
  }) {
    if (id.trim().isEmpty ||
        text.trim().isEmpty ||
        text.length > maxTextCharacters ||
        updatedAt.isBefore(createdAt) ||
        (scope == MemoryScope.global
            ? ownerId != null
            : ownerId == null || ownerId!.trim().isEmpty) ||
        (scope != MemoryScope.global && globalOptIn)) {
      throw ArgumentError('Invalid memory fact.');
    }
  }

  static const int maxTextCharacters = 1000;

  final String id;
  final MemoryScope scope;

  /// Conversation/room ID or workspace ID; global facts have no owner.
  final String? ownerId;
  final String text;
  final MemorySource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  /// Consent belongs to this fact. Missing/false never enables global recall.
  final bool globalOptIn;

  bool isExpired(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  MemoryFact edited({
    required String text,
    required DateTime updatedAt,
    DateTime? expiresAt,
    bool? globalOptIn,
  }) => MemoryFact(
    id: id,
    scope: scope,
    ownerId: ownerId,
    text: text.trim(),
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
    globalOptIn: globalOptIn ?? this.globalOptIn,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'scope': scope.name,
    'ownerId': ownerId,
    'text': text,
    'source': source.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'globalOptIn': globalOptIn,
  };

  static MemoryFact? fromJson(Object? value) {
    if (value is! Map) return null;
    T? enumValue<T extends Enum>(List<T> values, Object? name) {
      for (final candidate in values) {
        if (candidate.name == name) return candidate;
      }
      return null;
    }

    DateTime? date(Object? raw) =>
        raw is String ? DateTime.tryParse(raw) : null;
    final id = value['id'];
    final text = value['text'];
    final scope = enumValue(MemoryScope.values, value['scope']);
    final source = enumValue(MemorySource.values, value['source']);
    final createdAt = date(value['createdAt']);
    final updatedAt = date(value['updatedAt']);
    final expiresAt = date(value['expiresAt']);
    final ownerId = value['ownerId'];
    final optIn = value['globalOptIn'];
    if (id is! String ||
        text is! String ||
        scope == null ||
        source == null ||
        createdAt == null ||
        updatedAt == null ||
        (ownerId != null && ownerId is! String) ||
        (optIn != null && optIn is! bool) ||
        (value['expiresAt'] != null && expiresAt == null)) {
      return null;
    }
    try {
      return MemoryFact(
        id: id,
        scope: scope,
        ownerId: ownerId as String?,
        text: text,
        source: source,
        createdAt: createdAt,
        updatedAt: updatedAt,
        expiresAt: expiresAt,
        globalOptIn: optIn == true,
      );
    } on ArgumentError {
      return null;
    }
  }
}
