// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Application-level controller for conversation lifecycle: listing, opening,
/// creating, renaming, pinning, deleting, exporting and importing.

@ProviderFor(ConversationController)
final conversationControllerProvider = ConversationControllerProvider._();

/// Application-level controller for conversation lifecycle: listing, opening,
/// creating, renaming, pinning, deleting, exporting and importing.
final class ConversationControllerProvider
    extends $NotifierProvider<ConversationController, ConversationListState> {
  /// Application-level controller for conversation lifecycle: listing, opening,
  /// creating, renaming, pinning, deleting, exporting and importing.
  ConversationControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationControllerHash();

  @$internal
  @override
  ConversationController create() => ConversationController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationListState>(value),
    );
  }
}

String _$conversationControllerHash() =>
    r'87fbbfced27f2fc344a8685aad6e5cda807e5a3b';

/// Application-level controller for conversation lifecycle: listing, opening,
/// creating, renaming, pinning, deleting, exporting and importing.

abstract class _$ConversationController
    extends $Notifier<ConversationListState> {
  ConversationListState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ConversationListState, ConversationListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConversationListState, ConversationListState>,
              ConversationListState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
