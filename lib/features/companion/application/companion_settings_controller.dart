import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/companion/data/companion_settings_store.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';

/// The settings file, opened once per session.
final companionSettingsStoreProvider = FutureProvider<CompanionSettingsStore>(
  (ref) => CompanionSettingsStore.open(),
);

/// The stored Companion preferences plus their load state.
class CompanionSettingsState {
  const CompanionSettingsState({
    this.settings = const CompanionSettings(),
    this.isReady = false,
    this.isReadOnly = false,
    this.errorMessage,
  });

  final CompanionSettings settings;

  /// False until the stored settings have been read.
  final bool isReady;

  /// True when the file belongs to a newer build, which makes the screen
  /// display-only.
  final bool isReadOnly;

  final String? errorMessage;

  CompanionSettingsState copyWith({
    CompanionSettings? settings,
    bool? isReady,
    bool? isReadOnly,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CompanionSettingsState(
      settings: settings ?? this.settings,
      isReady: isReady ?? this.isReady,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

final companionSettingsProvider =
    NotifierProvider<CompanionSettingsNotifier, CompanionSettingsState>(
      CompanionSettingsNotifier.new,
    );

/// Owns the Companion's name, its on/off switch and its tuning.
///
/// Every change is written immediately, and a failed write puts the previous
/// values back so the screen never shows a preference that was not stored.
class CompanionSettingsNotifier extends Notifier<CompanionSettingsState> {
  @override
  CompanionSettingsState build() {
    _load();
    return const CompanionSettingsState();
  }

  Future<void> _load() async {
    try {
      final store = await ref.read(companionSettingsStoreProvider.future);
      if (!ref.mounted) return;
      state = CompanionSettingsState(
        settings: store.load(),
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'The Companion settings were written by a newer version of '
                  'InstaLLM and are read-only in this build.'
            : null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load the Companion settings: $error',
      );
    }
  }

  /// Turns the Companion on or off.
  Future<bool> setEnabled(bool enabled) {
    return _apply(state.settings.copyWith(enabled: enabled));
  }

  /// Stores a name, refusing one the app cannot use.
  Future<bool> setName(String raw) {
    if (CompanionSettings.validateName(raw) != null) return Future.value(false);
    return _apply(state.settings.copyWith(name: raw.trim()));
  }

  /// Stores the wake sensitivity, clamped to 0..1.
  Future<bool> setWakeSensitivity(double value) {
    if (!value.isFinite) return Future.value(false);
    return _apply(
      state.settings.copyWith(wakeSensitivity: value.clamp(0.0, 1.0)),
    );
  }

  /// Stores how long a silence ends the turn, clamped and stepped.
  Future<bool> setSilenceTimeout(Duration value) {
    return _apply(state.settings.copyWith(silenceTimeout: value));
  }

  /// Clears the last error once it has been shown.
  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  Future<bool> _apply(CompanionSettings settings) async {
    if (state.isReadOnly) {
      state = state.copyWith(
        errorMessage:
            'The Companion settings were written by a newer version of '
            'InstaLLM and are read-only in this build.',
      );
      return false;
    }

    final normalized = settings.normalized();
    final previous = state.settings;
    state = state.copyWith(settings: normalized, clearError: true);

    try {
      final store = await ref.read(companionSettingsStoreProvider.future);
      if (store.save(normalized)) return true;
      if (!ref.mounted) return false;
      state = state.copyWith(
        settings: previous,
        errorMessage: store.isReadOnly
            ? 'The Companion settings were written by a newer version of '
                  'InstaLLM and are read-only in this build.'
            : 'Could not save the Companion settings on this device.',
      );
      return false;
    } catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        settings: previous,
        errorMessage: 'Could not save the Companion settings: $error',
      );
      return false;
    }
  }
}
