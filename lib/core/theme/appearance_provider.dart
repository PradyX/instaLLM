import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
    StateNotifierProvider<AppearanceNotifier, AppearanceState>(
      (ref) =>
          AppearanceNotifier(() => ref.read(appearanceStoreProvider.future)),
    );

class AppearanceNotifier extends StateNotifier<AppearanceState> {
  AppearanceNotifier(this._store) : super(const AppearanceState()) {
    _load();
  }

  final Future<AppearanceStore> Function() _store;

  Future<void> _load() async {
    try {
      final store = await _store();
      final preferences = store.load();
      if (!mounted) return;
      state = AppearanceState(
        preferences: preferences,
        isReady: true,
        isReadOnly: store.isReadOnly,
        error: store.isReadOnly ? AppearanceError.newerVersion : null,
      );
    } catch (_) {
      if (mounted) {
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
      if (!mounted) return false;
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
      if (mounted) {
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
