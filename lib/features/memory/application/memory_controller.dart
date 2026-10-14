import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/id_generator.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';
import 'package:installm/i18n/strings.g.dart';

final memoryStoreProvider = FutureProvider<MemoryStore>(
  (ref) => MemoryStore.open(),
);

class MemoryState {
  const MemoryState({
    this.facts = const [],
    this.isReady = false,
    this.isReadOnly = false,
    this.errorMessage,
    this.conversationWorkspaces = const {},
  });

  final List<MemoryFact> facts;
  final bool isReady;
  final bool isReadOnly;
  final String? errorMessage;
  final Map<String, String> conversationWorkspaces;
}

final memoryProvider = StateNotifierProvider<MemoryNotifier, MemoryState>(
  (ref) => MemoryNotifier(ref),
);

/// Explicit operations only: no automatic extraction, network, or sync.
class MemoryNotifier extends StateNotifier<MemoryState> {
  MemoryNotifier(this._ref) : super(const MemoryState()) {
    whenReady = _load();
  }

  final Ref _ref;
  late final Future<void> whenReady;
  MemoryStore? _store;
  String? get errorMessage => state.errorMessage;

  Future<void> _load() async {
    try {
      final store = await _ref.read(memoryStoreProvider.future);
      final facts = store.load();
      _store = store;
      if (!mounted) return;
      state = MemoryState(
        facts: facts,
        conversationWorkspaces: store.conversationWorkspaces,
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly ? t.memory.unsupported : null,
      );
    } catch (_) {
      if (!mounted) return;
      state = MemoryState(isReady: true, errorMessage: t.memory.readError);
    }
  }

  bool _error(String message) {
    state = MemoryState(
      facts: state.facts,
      conversationWorkspaces: state.conversationWorkspaces,
      isReady: state.isReady,
      isReadOnly: _store?.isReadOnly ?? state.isReadOnly,
      errorMessage: message,
    );
    return false;
  }

  bool _save(
    List<MemoryFact> facts, {
    Map<String, String>? conversationWorkspaces,
  }) {
    final bindings = conversationWorkspaces ?? state.conversationWorkspaces;
    if (_store == null ||
        !_store!.save(facts, conversationWorkspaces: bindings)) {
      return _error(
        _store?.isReadOnly == true
            ? t.memory.unsupportedEdit
            : t.memory.storageError,
      );
    }
    state = MemoryState(
      facts: List.unmodifiable(facts),
      isReady: true,
      conversationWorkspaces: Map.unmodifiable(bindings),
    );
    return true;
  }

  Future<MemoryFact?> remember({
    required String text,
    MemoryScope scope = MemoryScope.conversation,
    String? ownerId,
    MemorySource source = MemorySource.userStated,
    DateTime? expiresAt,
    bool globalOptIn = false,
  }) async {
    await whenReady;
    if (!mounted) return null;
    if (scope == MemoryScope.global && !globalOptIn) {
      _error(t.memory.consentError);
      return null;
    }
    final now = DateTime.now();
    final MemoryFact fact;
    try {
      fact = MemoryFact(
        id: IdGenerator.generate('fact'),
        scope: scope,
        ownerId: ownerId,
        text: text.trim(),
        source: source,
        createdAt: now,
        updatedAt: now,
        expiresAt: expiresAt,
        globalOptIn: globalOptIn,
      );
    } on ArgumentError {
      _error(t.memory.ownerTextError);
      return null;
    }
    return _save([...state.facts, fact]) ? fact : null;
  }

  /// Editing preserves scope/provenance; consent changes must be explicit.
  /// Omitting expiry keeps it; [clearExpiry] explicitly removes it.
  Future<bool> edit(
    String id, {
    required String text,
    DateTime? expiresAt,
    bool clearExpiry = false,
    bool? globalOptIn,
  }) async {
    await whenReady;
    if (!mounted) return false;
    final index = state.facts.indexWhere((fact) => fact.id == id);
    if (index < 0) return _error(t.memory.missingFact);
    final existing = state.facts[index];
    final MemoryFact updated;
    try {
      final now = DateTime.now();
      updated = existing.edited(
        text: text,
        updatedAt: now.isBefore(existing.updatedAt) ? existing.updatedAt : now,
        expiresAt: clearExpiry ? null : expiresAt ?? existing.expiresAt,
        globalOptIn: globalOptIn,
      );
    } on ArgumentError {
      return _error(t.memory.textError);
    }
    return _save([...state.facts]..[index] = updated);
  }

  Future<bool> forget(String id) async {
    await whenReady;
    if (!mounted) return false;
    if (!state.facts.any((fact) => fact.id == id)) {
      return _error(t.memory.missingFact);
    }
    return _save(state.facts.where((fact) => fact.id != id).toList());
  }

  /// A conversation keeps the workspace first chosen for memory. Selecting a
  /// different workspace later never silently changes this boundary.
  Future<bool> bindConversation(String id, String workspaceId) async {
    await whenReady;
    if (!mounted) return false;
    if (state.conversationWorkspaces.containsKey(id)) return true;
    if (id.isEmpty || workspaceId.isEmpty) return false;
    return _save(
      state.facts,
      conversationWorkspaces: {
        ...state.conversationWorkspaces,
        id: workspaceId,
      },
    );
  }

  Future<String> forgetText({
    required String text,
    required MemoryScope scope,
    String? ownerId,
  }) async {
    await whenReady;
    String normalized(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (!mounted) return t.memory.saveError;
    final matches = state.facts
        .where(
          (fact) =>
              fact.scope == scope &&
              fact.ownerId == ownerId &&
              normalized(fact.text) == normalized(text),
        )
        .toList();
    if (matches.isEmpty) return t.memory.noMatch;
    if (matches.length > 1) return t.memory.ambiguous;
    return await forget(matches.single.id)
        ? t.memory.forgotten
        : state.errorMessage ?? t.memory.saveError;
  }

  /// Bot scope is a recall ceiling. Narrower facts accompany the current
  /// conversation; wider facts require the bot's broader scope and consent.
  String promptFacts({
    required BotMemoryScope scope,
    required String conversationId,
    String? workspaceId,
    int maxTokens = 256,
    DateTime? now,
  }) {
    if (scope == BotMemoryScope.none || maxTokens <= 0) return '';
    final time = now ?? DateTime.now();
    final eligible = state.facts.where((fact) {
      if (fact.isExpired(time)) return false;
      return switch (fact.scope) {
        MemoryScope.conversation => fact.ownerId == conversationId,
        MemoryScope.workspace =>
          scope.index >= BotMemoryScope.workspace.index &&
              fact.ownerId == workspaceId,
        MemoryScope.global =>
          scope == BotMemoryScope.global && fact.globalOptIn,
      };
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    var result = '';
    for (final fact in eligible) {
      final text = fact.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final line = '- [${fact.scope.name}; ${fact.source.name}] $text';
      final candidate = result.isEmpty ? line : '$result\n$line';
      // Keep whole facts, not partial claims. The caller's context builder
      // also charges the completed system/goal prompt against its window.
      if (TokenEstimator.estimateText(candidate) <= maxTokens) {
        result = candidate;
      }
    }
    return result;
  }
}
