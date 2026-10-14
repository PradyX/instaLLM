import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/utils/id_generator.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/conversations/domain/context_policy.dart';
import 'package:installm/features/memory/data/memory_store.dart';
import 'package:installm/features/memory/domain/memory_fact.dart';

final memoryStoreProvider = FutureProvider<MemoryStore>(
  (ref) => MemoryStore.open(),
);

class MemoryState {
  const MemoryState({
    this.facts = const [],
    this.isReady = false,
    this.isReadOnly = false,
    this.errorMessage,
  });

  final List<MemoryFact> facts;
  final bool isReady;
  final bool isReadOnly;
  final String? errorMessage;
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

  Future<void> _load() async {
    try {
      final store = await _ref.read(memoryStoreProvider.future);
      final facts = store.load();
      _store = store;
      if (!mounted) return;
      state = MemoryState(
        facts: facts,
        isReady: true,
        isReadOnly: store.isReadOnly,
        errorMessage: store.isReadOnly
            ? 'Saved memory uses an unsupported format. Update InstaLLM '
                  'to edit it; the file has been left untouched.'
            : null,
      );
    } catch (_) {
      if (!mounted) return;
      state = const MemoryState(
        isReady: true,
        errorMessage:
            'Could not read saved memory. Check access to the '
            'app support folder and try again. Local chat remains available.',
      );
    }
  }

  bool _error(String message) {
    state = MemoryState(
      facts: state.facts,
      isReady: state.isReady,
      isReadOnly: _store?.isReadOnly ?? state.isReadOnly,
      errorMessage: message,
    );
    return false;
  }

  bool _save(List<MemoryFact> facts) {
    if (_store == null || !_store!.save(facts)) {
      return _error(
        _store?.isReadOnly == true
            ? 'Saved memory uses an unsupported format. Update InstaLLM '
                  'before editing it.'
            : 'Could not save memory. Check free space and access to the '
                  'app support folder, then try again. Existing facts were kept.',
      );
    }
    state = MemoryState(facts: List.unmodifiable(facts), isReady: true);
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
      _error(
        'Confirm sharing this fact across all workspaces before saving it.',
      );
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
      _error(
        'Enter one fact of up to ${MemoryFact.maxTextCharacters} '
        'characters and choose its conversation or workspace.',
      );
      return null;
    }
    return _save([...state.facts, fact]) ? fact : null;
  }

  /// Editing preserves scope, provenance, and the fact's original consent.
  /// Omitting expiry keeps it; [clearExpiry] explicitly removes it.
  Future<bool> edit(
    String id, {
    required String text,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) async {
    await whenReady;
    if (!mounted) return false;
    final index = state.facts.indexWhere((fact) => fact.id == id);
    if (index < 0) return _error('This memory fact no longer exists.');
    final existing = state.facts[index];
    final MemoryFact updated;
    try {
      final now = DateTime.now();
      updated = existing.edited(
        text: text,
        updatedAt: now.isBefore(existing.updatedAt) ? existing.updatedAt : now,
        expiresAt: clearExpiry ? null : expiresAt ?? existing.expiresAt,
      );
    } on ArgumentError {
      return _error(
        'Enter one fact of up to '
        '${MemoryFact.maxTextCharacters} characters.',
      );
    }
    return _save([...state.facts]..[index] = updated);
  }

  Future<bool> forget(String id) async {
    await whenReady;
    if (!mounted) return false;
    if (!state.facts.any((fact) => fact.id == id)) {
      return _error('This memory fact no longer exists.');
    }
    return _save(state.facts.where((fact) => fact.id != id).toList());
  }

  /// Bot scope is a recall ceiling. Narrower facts accompany the current
  /// conversation; wider facts require the bot's broader scope and consent.
  String promptFacts({
    required BotMemoryScope scope,
    required String conversationId,
    required String workspaceId,
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
