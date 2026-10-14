import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/id_generator.dart';
import 'package:installm/features/bots/data/bot_store.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/bots/domain/built_in_bots.dart';

/// Bot registry file, opened once per session.
final botStoreProvider = FutureProvider<BotStore>((ref) => BotStore.open());

class BotsState {
  const BotsState({
    this.bots = const [],
    this.isReady = false,
    this.errorMessage,
    this.isReadOnly = false,
  });

  final List<Bot> bots;
  final bool isReady;
  final String? errorMessage;
  final bool isReadOnly;

  Bot? botById(String? id) {
    if (id == null) return null;
    for (final bot in bots) {
      if (bot.id == id) return bot;
    }
    return null;
  }

  BotsState copyWith({
    List<Bot>? bots,
    bool? isReady,
    String? errorMessage,
    bool clearError = false,
    bool? isReadOnly,
  }) {
    return BotsState(
      bots: bots ?? this.bots,
      isReady: isReady ?? this.isReady,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final botsProvider = StateNotifierProvider<BotsNotifier, BotsState>(
  (ref) => BotsNotifier(ref),
);

/// Owns the bot registry.
///
/// Only user-created bots enter the registry. Optional templates create
/// editable copies. Bots are full records: soul, model and profile choice,
/// skills, MCP servers, tool permissions, memory scope and workspaces.
class BotsNotifier extends StateNotifier<BotsState> {
  BotsNotifier(this._ref) : super(const BotsState()) {
    _loaded = _load();
  }

  final Ref _ref;
  late final Future<void> _loaded;
  Future<void> get whenReady => _loaded;
  Future<void> _pending = Future<void>.value();

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _pending.then((_) async {
      await _loaded;
      return action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _load() async {
    try {
      final store = await _ref.read(botStoreProvider.future);
      final snapshot = store.load();
      state = BotsState(
        bots: snapshot.allBots,
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'Bots were written by a newer version of InstaLLM and are '
                  'read-only in this build.'
            : null,
      );
    } catch (error) {
      state = state.copyWith(
        isReady: true,
        errorMessage: 'Could not load bots: $error',
      );
    }
  }

  Future<bool> _persist(List<Bot> bots) async {
    try {
      final store = await _ref.read(botStoreProvider.future);
      if (store.isReadOnly) {
        state = state.copyWith(
          errorMessage:
              'Bots were written by a newer version and are '
              'read-only in this build.',
        );
        return false;
      }
      if (!store.save(BotsSnapshot(customBots: bots))) {
        state = state.copyWith(errorMessage: 'Could not save bots.');
        return false;
      }
      state = state.copyWith(bots: bots, clearError: true);
      return true;
    } catch (error) {
      state = state.copyWith(errorMessage: 'Could not save bots: $error');
      return false;
    }
  }

  /// Duplicates [templateId] into an editable custom bot.
  Future<Bot?> duplicateTemplate(String templateId) {
    final template = BuiltInBots.byId(templateId);
    if (template == null) return Future.value(null);
    return createBot(template.name, templateId: templateId);
  }

  Future<Bot?> createBot(String name, {String? templateId, String? soul}) =>
      _mutate(() async {
        final template = templateId == null
            ? null
            : BuiltInBots.byId(templateId);
        if (templateId != null && template == null) return null;
        final bot = Bot.create(
          id: IdGenerator.generate('bot'),
          name: name,
          icon: template?.icon ?? '🤖',
          description: template?.description ?? '',
          soul: soul ?? template?.soul ?? '',
          modelId: template?.modelId,
          contextPolicyId: template?.contextPolicyId,
          inferenceProfileId: template?.inferenceProfileId,
          skillIds: template?.skillIds ?? const [],
          mcpServerIds: template?.mcpServerIds ?? const [],
          toolPermissions: template?.toolPermissions ?? const {},
          memoryScope: template?.memoryScope ?? BotMemoryScope.workspace,
          workspaceIds: template?.workspaceIds ?? const [],
        );
        final saved = await _persist([...state.bots, bot]);
        return saved ? bot : null;
      });

  Future<bool> updateBot(Bot bot) => _mutate(() async {
    if (bot.isBuiltIn) return false;
    if (state.botById(bot.id) == null) return false;
    return _persist([
      for (final candidate in state.bots)
        if (candidate.id == bot.id) bot else candidate,
    ]);
  });

  Future<bool> removeBot(String botId) => _mutate(() async {
    final bot = state.botById(botId);
    if (bot == null || bot.isBuiltIn) return false;
    return _persist([
      for (final candidate in state.bots)
        if (candidate.id != botId) candidate,
    ]);
  });

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
