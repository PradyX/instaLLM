import 'dart:io';

import 'package:flutter/services.dart';
import 'package:installm/features/artifacts/data/chat_export.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where an export was written, and how to hand it to another program.
class ChatExportLocation {
  const ChatExportLocation({required this.path, required this.label});

  /// A file path, or — on Android — the `content://` URI MediaStore returned.
  final String path;

  /// What to tell the user, e.g. `Downloads/setup-notes-20261123-0250.pdf`.
  final String label;

  /// True when [path] is a content URI rather than a plain file path.
  bool get isContentUri => path.startsWith('content://');
}

/// Gets an exported conversation somewhere another program can open it
/// (Road Map 5 Phase 5.0).
///
/// The save dialog decides on desktop. Android has no save dialog in
/// `file_selector`, so the file goes into the public Downloads collection
/// through MediaStore — the app's own folder is invisible to a viewer — and
/// [open] hands it to whichever app the system offers. Everything here is
/// best effort: a platform that cannot do either leaves the caller with its own
/// exports folder, which is still a real file on disk.
abstract final class ChatExportStore {
  static const MethodChannel _channel = MethodChannel('installm/exports');

  /// Writes [bytes] into Downloads on Android; null anywhere else or on
  /// failure, so the caller falls back to its own folder.
  static Future<ChatExportLocation?> saveToDownloads({
    required String name,
    required ChatExportFormat format,
    required Uint8List bytes,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMapMethod<String, String>(
        'saveToDownloads',
        {'name': name, 'mimeType': format.mimeType, 'bytes': bytes},
      );
      final uri = result?['uri'];
      if (uri == null || uri.isEmpty) return null;
      return ChatExportLocation(
        path: uri,
        label: result?['displayPath'] ?? name,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens a saved export in another program.
  ///
  /// False when no app could take it, which the caller reports instead of
  /// claiming the file opened.
  static Future<bool> open({
    required ChatExportLocation location,
    required ChatExportFormat format,
  }) async {
    if (location.isContentUri) {
      try {
        return await _channel.invokeMethod<bool>('openFile', {
              'uri': location.path,
              'mimeType': format.mimeType,
            }) ??
            false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    try {
      return await launchUrl(Uri.file(location.path));
    } catch (_) {
      return false;
    }
  }
}
