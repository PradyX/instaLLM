/// Multi-device 2.0 (Road Map 3 Phase 3.8).
///
/// Handoff without hand-holding: continue a chat on the other device via
/// vault-carried state. Models stay per-device; the move is an explicit
/// "pick up", never a silent migration. Device-specific choices never sync.
class HandoffPackage {
  const HandoffPackage({
    required this.chatId,
    required this.title,
    required this.exportedAt,
    required this.messages,
    this.modelId,
  });

  /// Chat the package continues.
  final String chatId;
  final String title;
  final DateTime exportedAt;

  /// Message history: role/text pairs. Models stay per-device, so no weights
  /// or device paths travel — the other device answers with its own model.
  final List<HandoffMessage> messages;

  /// Model that answered here, for display only. Never resolved remotely.
  final String? modelId;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'chatId': chatId,
    'title': title,
    'exportedAt': exportedAt.toIso8601String(),
    'modelId': modelId,
    'messages': messages.map((entry) => entry.toJson()).toList(),
  };

  static HandoffPackage? fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) return null;
    final chatId = json['chatId'];
    if (chatId is! String || chatId.isEmpty) return null;
    final messages = <HandoffMessage>[];
    if (json['messages'] is List) {
      for (final entry in (json['messages'] as List).take(1000)) {
        if (entry is! Map) continue;
        final message = HandoffMessage.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (message != null) messages.add(message);
      }
    }
    if (messages.isEmpty) return null;
    return HandoffPackage(
      chatId: chatId,
      title: json['title'] is String ? json['title'] as String : 'Handoff',
      exportedAt:
          DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
      modelId: json['modelId'] as String?,
    );
  }
}

/// One line of a handoff: who said what. No attachments, no paths.
class HandoffMessage {
  const HandoffMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};

  static HandoffMessage? fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    final text = json['text'];
    if (role is! String || text is! String) return null;
    if (text.trim().isEmpty) return null;
    return HandoffMessage(role: role, text: text);
  }
}

/// Per-device choices that never sync (Road Map 3 Phase 3.8).
///
/// Model, performance and notification choices belong to the hardware in the
/// hand, not to the vault. This object is stored locally only and excluded
/// from backup/sync by construction: no exporter reads it.
class DeviceProfile {
  const DeviceProfile({
    this.modelId,
    this.performanceLevel = 'balanced',
    this.notificationsEnabled = true,
  });

  /// Installed model this device answers with. A model id that is not
  /// installed here resolves to the device's own default — never fetched.
  final String? modelId;

  /// `efficient`, `balanced` or `performance`. Advisory only.
  final String performanceLevel;

  final bool notificationsEnabled;

  static const List<String> knownLevels = [
    'efficient',
    'balanced',
    'performance',
  ];

  DeviceProfile normalized() {
    final level = performanceLevel.trim().toLowerCase();
    return DeviceProfile(
      modelId: modelId?.trim().isEmpty == true ? null : modelId?.trim(),
      performanceLevel: knownLevels.contains(level) ? level : 'balanced',
      notificationsEnabled: notificationsEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'performanceLevel': performanceLevel,
    'notificationsEnabled': notificationsEnabled,
  };

  static DeviceProfile fromJson(Object? raw) {
    if (raw is! Map) return const DeviceProfile();
    final map = Map<String, dynamic>.from(raw);
    return DeviceProfile(
      modelId: map['modelId'] is String ? map['modelId'] as String : null,
      performanceLevel: map['performanceLevel'] is String
          ? map['performanceLevel'] as String
          : 'balanced',
      notificationsEnabled: map['notificationsEnabled'] is bool
          ? map['notificationsEnabled'] as bool
          : true,
    ).normalized();
  }
}

/// Result of the "verify sync health" check (Road Map 3 Phase 3.8).
class SyncHealth {
  const SyncHealth({
    required this.vaultReachable,
    required this.conflictCount,
    required this.lastChecked,
    this.detail = '',
  });

  /// False when the vault folder is missing or unreadable here.
  final bool vaultReachable;
  final int conflictCount;
  final DateTime lastChecked;
  final String detail;

  bool get isHealthy => vaultReachable && conflictCount == 0;

  String summary() {
    if (!vaultReachable) {
      return 'Vault folder is not reachable on this device. $detail';
    }
    if (conflictCount > 0) {
      return '$conflictCount sync conflict${conflictCount == 1 ? '' : 's'} need${conflictCount == 1 ? 's' : ''} a decision in the workspace.';
    }
    return 'Sync looks healthy.';
  }
}
