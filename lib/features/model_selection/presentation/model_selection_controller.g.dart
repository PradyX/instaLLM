// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_selection_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ModelSelectionController)
final modelSelectionControllerProvider = ModelSelectionControllerProvider._();

final class ModelSelectionControllerProvider
    extends $NotifierProvider<ModelSelectionController, ModelSelectionState> {
  ModelSelectionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelSelectionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelSelectionControllerHash();

  @$internal
  @override
  ModelSelectionController create() => ModelSelectionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModelSelectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModelSelectionState>(value),
    );
  }
}

String _$modelSelectionControllerHash() =>
    r'11c6224d072a8f0a235ea34f3b4e4da15552d422';

abstract class _$ModelSelectionController
    extends $Notifier<ModelSelectionState> {
  ModelSelectionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ModelSelectionState, ModelSelectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ModelSelectionState, ModelSelectionState>,
              ModelSelectionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
