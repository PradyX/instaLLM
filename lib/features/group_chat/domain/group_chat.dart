import 'package:pocket_llm/core/utils/id_generator.dart';

/// Who answers next in a group chat (Road Map 2 §11.1).
enum SpeakerMode {
  /// Only a mentioned bot responds (`@planner ...`).
  manual('Manual'),

  /// A local relevance vote picks the next bot. Optional, off by default.
  auto('Auto');

  const SpeakerMode(this.label);
  final String label;
}

/// One project chat shared by the user and several bots.
///
/// A direct chat ([directBotId] set) is one bot's canonical room: every
/// user line is for them, no `@mention` needed, and exactly one answer
/// follows. Rooms stay multi-speaker with mention routing.
class GroupChat {
  const GroupChat({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.memberBotIds = const [],
    this.directBotId,
    this.modelId,
    this.mode = SpeakerMode.manual,
    this.maxRounds = defaultMaxRounds,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Every run is bounded (§11.2): rounds, tokens (via the context budget)
  /// and a cancel button. No cap means no run.
  static const int defaultMaxRounds = 10;
  static const int minMaxRounds = 2;
  static const int maxMaxRounds = 30;

  factory GroupChat.create({
    String? id,
    required String workspaceId,
    required String name,
    List<String> memberBotIds = const [],
    String? directBotId,
    String? modelId,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    return GroupChat(
      id: id ?? IdGenerator.generate('groupchat'),
      workspaceId: workspaceId,
      name: name.trim().isEmpty ? 'Group chat' : name.trim(),
      memberBotIds: memberBotIds,
      directBotId: directBotId,
      modelId: modelId,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  final String id;
  final String workspaceId;
  final String name;
  final List<String> memberBotIds;

  /// The bot this room belongs to, when it is a 1:1 direct chat.
  /// Null for group rooms. Old documents without the key read as rooms.
  final String? directBotId;

  /// True for a bot's canonical 1:1 chat.
  bool get isDirect => directBotId != null;

  /// The model this room answers on, chosen in its composer. Null follows
  /// the bot's own preferred model, then the first tool-capable model that
  /// is installed.
  ///
  /// It lives on the room rather than on the bot because a built-in bot is
  /// read-only, and because picking a model for one room should not move
  /// the bot in every other room it answers in. Old documents without the
  /// key read as null.
  final String? modelId;

  final SpeakerMode mode;
  final int maxRounds;
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupChat copyWith({
    String? name,
    List<String>? memberBotIds,
    String? directBotId,
    String? modelId,
    bool clearModel = false,
    SpeakerMode? mode,
    int? maxRounds,
    DateTime? updatedAt,
  }) {
    return GroupChat(
      id: id,
      workspaceId: workspaceId,
      name: (name ?? this.name).trim().isEmpty
          ? 'Group chat'
          : (name ?? this.name).trim(),
      memberBotIds: memberBotIds ?? this.memberBotIds,
      directBotId: directBotId ?? this.directBotId,
      modelId: clearModel ? null : (modelId ?? this.modelId),
      mode: mode ?? this.mode,
      maxRounds: (maxRounds ?? this.maxRounds).clamp(
        minMaxRounds,
        maxMaxRounds,
      ),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workspaceId': workspaceId,
      'name': name,
      'memberBotIds': memberBotIds,
      'directBotId': directBotId,
      'modelId': modelId,
      'mode': mode.name,
      'maxRounds': maxRounds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static GroupChat? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final workspaceId = json['workspaceId'];
    final name = json['name'];
    if (id is! String || workspaceId is! String || name is! String) {
      return null;
    }
    List<String> readStrings(Object? value) {
      if (value is! List) return const [];
      return value.whereType<String>().toList(growable: false);
    }

    DateTime parseDate(Object? value) {
      if (value is String) {
        return DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    String? readOpt(Object? value) => value is String ? value : null;
    return GroupChat(
      id: id,
      workspaceId: workspaceId,
      name: name,
      memberBotIds: readStrings(json['memberBotIds']),
      directBotId: readOpt(json['directBotId']),
      modelId: readOpt(json['modelId']),
      mode: SpeakerMode.values.firstWhere(
        (candidate) => candidate.name == json['mode'],
        orElse: () => SpeakerMode.manual,
      ),
      maxRounds: json['maxRounds'] is num
          ? (json['maxRounds'] as num).toInt()
          : defaultMaxRounds,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    ).copyWith();
  }
}

/// One line of a group chat: the user or one bot.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.chatId,
    this.authorBotId,
    required this.authorName,
    required this.text,
    this.pendingPrompt,
    required this.createdAt,
  });

  factory GroupMessage.user({
    String? id,
    required String chatId,
    required String text,
    DateTime? now,
  }) {
    return GroupMessage(
      id: id ?? IdGenerator.generate('gmsg'),
      chatId: chatId,
      authorName: 'You',
      text: text,
      createdAt: now ?? DateTime.now(),
    );
  }

  factory GroupMessage.bot({
    String? id,
    required String chatId,
    required String botId,
    required String botName,
    required String text,
    String? pendingPrompt,
    DateTime? now,
  }) {
    return GroupMessage(
      id: id ?? IdGenerator.generate('gmsg'),
      chatId: chatId,
      authorBotId: botId,
      authorName: botName,
      text: text,
      pendingPrompt: pendingPrompt,
      createdAt: now ?? DateTime.now(),
    );
  }

  final String id;
  final String chatId;

  /// Null for the user's own lines.
  final String? authorBotId;
  final String authorName;
  final String text;

  /// Set when the bot has not answered yet: the assembled prompt waiting
  /// for a model (or a pasted reply).
  final String? pendingPrompt;
  final DateTime createdAt;

  bool get isUser => authorBotId == null;
  bool get isPending => pendingPrompt != null;

  GroupMessage copyWith({String? text, String? pendingPrompt}) {
    return GroupMessage(
      id: id,
      chatId: chatId,
      authorBotId: authorBotId,
      authorName: authorName,
      text: text ?? this.text,
      pendingPrompt: pendingPrompt ?? this.pendingPrompt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chatId': chatId,
      'authorBotId': authorBotId,
      'authorName': authorName,
      'text': text,
      'pendingPrompt': pendingPrompt,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static GroupMessage? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final chatId = json['chatId'];
    final authorName = json['authorName'];
    final text = json['text'];
    if (id is! String ||
        chatId is! String ||
        authorName is! String ||
        text is! String) {
      return null;
    }
    return GroupMessage(
      id: id,
      chatId: chatId,
      authorBotId: json['authorBotId'] is String
          ? json['authorBotId'] as String
          : null,
      authorName: authorName,
      text: text,
      pendingPrompt: json['pendingPrompt'] is String
          ? json['pendingPrompt'] as String
          : null,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String) ??
                DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
