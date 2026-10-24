import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/theme/appearance_preferences.dart';
import 'package:installm/core/theme/appearance_store.dart';

final appearanceStoreProvider = FutureProvider<AppearanceStore>(
  (ref) => AppearanceStore.open(),
);

enum AppearanceError { load, save, newerVersion }

class AppearanceState {
  const AppearanceState({
    this.preferences = const AppearancePreferences(),
    this.isReady = false,
    this.isReadOnly = false,
    this.error,
  });

  final AppearancePreferences preferences;
  final bool isReady;
  final bool isReadOnly;
  final AppearanceError? error;
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceState>(
      AppearanceNotifier.new,
    );

class AppearanceNotifier extends Notifier<AppearanceState> {
  @override
  AppearanceState build() {
    _load();
    return const AppearanceState();
  }

  Future<AppearanceStore> _store() => ref.read(appearanceStoreProvider.future);

  Future<void> _load() async {
    try {
      final store = await _store();
      final preferences = store.load();
      if (!ref.mounted) return;
      state = AppearanceState(
        preferences: preferences,
        isReady: true,
        isReadOnly: store.isReadOnly,
        error: store.isReadOnly ? AppearanceError.newerVersion : null,
      );
    } catch (_) {
      if (ref.mounted) {
        state = const AppearanceState(
          isReady: true,
          error: AppearanceError.load,
        );
      }
    }
  }

  Future<bool> setSurfaceStyle(SurfaceStyle style) =>
      _update(surfaceStyle: style);
  Future<bool> setAccent(AccentColor accent) => _update(accent: accent);
  Future<bool> setContrast(double contrast) => _update(contrast: contrast);
  Future<bool> setGlassOpacity(double opacity) =>
      _update(glassOpacity: opacity);

  Future<bool> _update({
    SurfaceStyle? surfaceStyle,
    AccentColor? accent,
    double? contrast,
    double? glassOpacity,
  }) async {
    if (!state.isReady || state.isReadOnly) return false;
    try {
      final store = await _store();
      if (!ref.mounted) return false;
      final preferences = state.preferences.copyWith(
        surfaceStyle: surfaceStyle,
        accent: accent,
        contrast: contrast,
        glassOpacity: glassOpacity,
      );
      if (!store.save(preferences)) {
        state = AppearanceState(
          preferences: state.preferences,
          isReady: true,
          isReadOnly: store.isReadOnly,
          error: store.isReadOnly
              ? AppearanceError.newerVersion
              : AppearanceError.save,
        );
        return false;
      }
      state = AppearanceState(preferences: preferences, isReady: true);
      return true;
    } catch (_) {
      if (ref.mounted) {
        state = AppearanceState(
          preferences: state.preferences,
          isReady: true,
          error: AppearanceError.save,
        );
      }
      return false;
    }
  }
}
