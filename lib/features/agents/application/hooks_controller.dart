import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/id_generator.dart';
import 'package:installm/features/agents/data/hook_store.dart';
import 'package:installm/features/agents/domain/agent_hook.dart';

/// Hook file, opened once per session.
final hookStoreProvider = FutureProvider<HookStore>((ref) => HookStore.open());

class HooksState {
  const HooksState({
    this.hooks = const [],
    this.isReady = false,
    this.errorMessage,
    this.isReadOnly = false,
  });

  final List<AgentHook> hooks;
  final bool isReady;
  final String? errorMessage;
  final bool isReadOnly;

  /// What the tool registry enforces: the built-in floor first, then the
  /// rules the user wrote. A built-in is never stored, edited or deleted, and
  /// being a hook it can only restrict.
  HookPolicy get policy => HookPolicy(hooks: [...BuiltInHooks.all, ...hooks]);

  AgentHook? hookById(String id) {
    for (final hook in hooks) {
      if (hook.id == id) return hook;
    }
    return null;
  }

  HooksState copyWith({
    List<AgentHook>? hooks,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
    bool? isReadOnly,
  }) {
    return HooksState(
      hooks: hooks ?? this.hooks,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final hooksProvider = NotifierProvider<HooksController, HooksState>(
  HooksController.new,
);

/// Owns the hook list: what is listed, what is on, and which rules are owed to
/// the user. Every change is one document write, and a store written by a newer
/// build stays read-only rather than being rewritten.
class HooksController extends Notifier<HooksState> {
  @override
  HooksState build() {
    _load();
    return const HooksState();
  }

  Future<void> get whenReady async {
    await ref.read(hookStoreProvider.future);
    while (!state.isReady && ref.mounted) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _load() async {
    try {
      final store = await ref.read(hookStoreProvider.future);
      final snapshot = store.load();
      state = HooksState(
        hooks: snapshot.hooks,
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'Hooks were written by a newer version of InstaLLM and are '
                  'read-only in this build.'
            : null,
      );
    } catch (error) {
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load hooks: $error',
      );
    }
  }

  Future<bool> _persist() async {
    try {
      final store = await ref.read(hookStoreProvider.future);
      if (store.isReadOnly) {
        state = state.copyWith(
          errorMessage:
              'Hooks were written by a newer version and are read-only in '
              'this build.',
        );
        return false;
      }
      return store.save(HooksSnapshot(hooks: state.hooks));
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not save hooks: $error');
      return false;
    }
  }

  /// Adds one rule. Null (with the reason in [HooksState.errorMessage]) when
  /// the rule has no name to list it under or the store refused the write.
  Future<AgentHook?> addHook({
    required String name,
    String toolPattern = '*',
    String resourcePattern = '',
    HookLevel level = HookLevel.refuse,
  }) async {
    if (name.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Give the hook a name so the list stays readable.',
      );
      return null;
    }
    await whenReady;
    final hook = AgentHook.create(
      id: IdGenerator.generate('hook'),
      name: name,
      toolPattern: toolPattern,
      resourcePattern: resourcePattern,
      level: level,
    );
    final previous = state;
    state = state.copyWith(hooks: [...state.hooks, hook], clearError: true);
    if (await _persist()) return hook;
    state = previous.copyWith(errorMessage: 'Could not save the hook.');
    return null;
  }

  /// Replaces one rule's fields. The id and creation time stay.
  Future<bool> updateHook(AgentHook hook) async {
    if (state.hookById(hook.id) == null) return false;
    if (hook.name.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'Give the hook a name so the list stays readable.',
      );
      return false;
    }
    state = state.copyWith(
      hooks: [
        for (final candidate in state.hooks)
          if (candidate.id == hook.id) hook else candidate,
      ],
      clearError: true,
    );
    return _persist();
  }

  Future<bool> setEnabled(String hookId, bool enabled) async {
    final hook = state.hookById(hookId);
    if (hook == null || hook.enabled == enabled) return false;
    state = state.copyWith(
      hooks: [
        for (final candidate in state.hooks)
          if (candidate.id == hookId)
            candidate.copyWith(enabled: enabled)
          else
            candidate,
      ],
      clearError: true,
    );
    return _persist();
  }

  Future<bool> removeHook(String hookId) async {
    if (state.hookById(hookId) == null) return false;
    state = state.copyWith(
      hooks: [
        for (final candidate in state.hooks)
          if (candidate.id != hookId) candidate,
      ],
      clearError: true,
    );
    return _persist();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
