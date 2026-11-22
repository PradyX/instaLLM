/// What another app handed to InstaLLM (Road Map 5 Phase 5.1).
///
/// Only the transport's own shape: the payload is never sent to a model here
/// and nothing is stored. Text becomes a composer draft, an attachment becomes
/// a pending attachment on the message being composed, and both wait for the
/// user to press send.
library;

/// A file another app shared, already copied into InstaLLM's own storage.
///
/// The copy matters: the content URI an Android app hands over can be revoked
/// the moment the sharing app leaves, so the composer holds a path it owns.
class SharedAttachment {
  const SharedAttachment({
    required this.path,
    required this.mimeType,
    required this.name,
  });

  /// Absolute path of the app's own copy.
  final String path;

  /// The MIME type the sharing app declared.
  final String mimeType;

  /// A readable name, from the sharing app when it offered one.
  final String name;

  bool get isImage => normalizedMimeType.startsWith('image/');

  /// The only document kind the share target accepts.
  bool get isPdf => normalizedMimeType == 'application/pdf';

  String get normalizedMimeType => mimeType.trim().toLowerCase();
}

/// One share: some text or a link, some files, or both.
class SharedPayload {
  const SharedPayload({this.text, this.attachments = const []});

  final String? text;
  final List<SharedAttachment> attachments;

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) && attachments.isEmpty;

  List<SharedAttachment> get images => [
    for (final attachment in attachments)
      if (attachment.isImage) attachment,
  ];

  List<SharedAttachment> get documents => [
    for (final attachment in attachments)
      if (!attachment.isImage) attachment,
  ];
}

/// Reads the platform's share payload, or null when there is nothing to stage.
///
/// Deliberately forgiving: a payload from a newer build, a missing key or an
/// entry without a path is skipped instead of failing the whole share, and a
/// file kind the composer cannot show is dropped rather than offered.
SharedPayload? sharedPayloadFromMap(Object? raw) {
  if (raw is! Map) return null;

  final rawText = raw['text'];
  final text = rawText is String && rawText.trim().isNotEmpty
      ? rawText.trim()
      : null;

  final attachments = <SharedAttachment>[];
  final rawAttachments = raw['attachments'];
  if (rawAttachments is List) {
    for (final entry in rawAttachments) {
      if (entry is! Map) continue;
      final path = entry['path'];
      final mimeType = entry['mimeType'];
      if (path is! String || path.trim().isEmpty) continue;
      if (mimeType is! String) continue;
      final attachment = SharedAttachment(
        path: path.trim(),
        mimeType: mimeType,
        name:
            entry['name'] is String &&
                (entry['name'] as String).trim().isNotEmpty
            ? (entry['name'] as String).trim()
            : path.split('/').last,
      );
      if (!_isAccepted(attachment)) continue;
      attachments.add(attachment);
    }
  }

  final payload = SharedPayload(text: text, attachments: attachments);
  return payload.isEmpty ? null : payload;
}

bool _isAccepted(SharedAttachment attachment) =>
    attachment.isImage || attachment.isPdf;
