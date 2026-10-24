import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:io';

import 'package:installm/features/connections/domain/connector_config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:installm/storage/secure_storage.dart';

/// Secure-storage keys are built by the domain helpers; this file holds only
/// server names and local paths, never passwords.

class ConnectorsState {
  const ConnectorsState({
    this.calendar = const CalendarConnector(),
    this.email = const EmailConnector(),
    this.isOpen = false,
    this.isReadOnly = false,
  });

  final CalendarConnector calendar;
  final EmailConnector email;
  final bool isOpen;
  final bool isReadOnly;

  ConnectorsState copyWith({
    CalendarConnector? calendar,
    EmailConnector? email,
    bool? isOpen,
    bool? isReadOnly,
  }) {
    return ConnectorsState(
      calendar: calendar ?? this.calendar,
      email: email ?? this.email,
      isOpen: isOpen ?? this.isOpen,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final connectorsProvider =
    NotifierProvider<ConnectorsNotifier, ConnectorsState>(
      ConnectorsNotifier.new,
    );

class ConnectorsNotifier extends Notifier<ConnectorsState> {
  @override
  ConnectorsState build() {
    _open();
    return const ConnectorsState();
  }

  File? _file;
  bool _readOnly = false;

  Future<File> _configFile() async {
    final existing = _file;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final file = File(p.join(support.path, 'connections', 'connectors.json'));
    _file = file;
    return file;
  }

  Future<void> _open() async {
    try {
      final file = await _configFile();
      if (!file.existsSync()) {
        state = state.copyWith(isOpen: true);
        return;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        state = state.copyWith(isOpen: true);
        return;
      }
      if (raw['version'] != 1) {
        _readOnly = true;
        state = state.copyWith(isOpen: true, isReadOnly: true);
        return;
      }
      state = state.copyWith(
        calendar: CalendarConnector.fromJson(raw['calendar']),
        email: EmailConnector.fromJson(raw['email']),
        isOpen: true,
      );
    } catch (_) {
      state = state.copyWith(isOpen: true);
    }
  }

  Future<bool> _persist() async {
    if (_readOnly) return false;
    try {
      final file = await _configFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'calendar': state.calendar.toJson(),
          'email': state.email.toJson(),
        }),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> addIcsPath(String path) async {
    if (_readOnly || path.trim().isEmpty) return;
    if (state.calendar.icsPaths.contains(path)) return;
    state = state.copyWith(
      calendar: CalendarConnector(
        icsPaths: [...state.calendar.icsPaths, path],
        caldavUrl: state.calendar.caldavUrl,
      ),
    );
    await _persist();
  }

  Future<void> removeIcsPath(String path) async {
    state = state.copyWith(
      calendar: CalendarConnector(
        icsPaths: [
          for (final entry in state.calendar.icsPaths)
            if (entry != path) entry,
        ],
        caldavUrl: state.calendar.caldavUrl,
      ),
    );
    await _persist();
  }

  Future<void> addMboxPath(String path) async {
    if (_readOnly || path.trim().isEmpty) return;
    if (state.email.mboxPaths.contains(path)) return;
    state = state.copyWith(
      email: EmailConnector(
        imapHost: state.email.imapHost,
        imapUser: state.email.imapUser,
        mboxPaths: [...state.email.mboxPaths, path],
      ),
    );
    await _persist();
  }

  Future<void> removeMboxPath(String path) async {
    state = state.copyWith(
      email: EmailConnector(
        imapHost: state.email.imapHost,
        imapUser: state.email.imapUser,
        mboxPaths: [
          for (final entry in state.email.mboxPaths)
            if (entry != path) entry,
        ],
      ),
    );
    await _persist();
  }

  /// Stores an IMAP password in secure storage; the config keeps host+user.
  Future<void> setImapPassword({
    required String host,
    required String user,
    required String password,
  }) {
    return SecureStorage.instance.writePrimitive(
      key: imapPasswordKey(host, user),
      value: password,
    );
  }

  Future<String?> readImapPassword({
    required String host,
    required String user,
  }) {
    return SecureStorage.instance.readPrimitive(imapPasswordKey(host, user));
  }
}
