import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:installm/features/documents/data/network_policy_store.dart';
import 'package:installm/features/documents/domain/network_policy.dart';
import 'package:installm/storage/secure_storage.dart';

/// Key prefix for per-workspace search API keys in secure storage.
///
/// Keys never live in the policy file: the file names the provider, secure
/// storage holds the secret. No credential leaves secure storage.
String webSearchKeyFor(String workspaceId, String provider) =>
    'web_search_key_${workspaceId}_${provider.trim().toLowerCase()}';

/// The network policy file on this device, opened once per session.
final networkPolicyStoreProvider = FutureProvider<NetworkPolicyStore>((
  ref,
) async {
  final store = await NetworkPolicyStore.open();
  return store;
});

/// What the network settings screen shows: one snapshot for every workspace.
class NetworkPolicyState {
  const NetworkPolicyState({
    this.snapshot = NetworkPolicySnapshot.empty,
    this.isOpen = false,
    this.isReadOnly = false,
  });

  final NetworkPolicySnapshot snapshot;
  final bool isOpen;
  final bool isReadOnly;

  NetworkPolicyState copyWith({
    NetworkPolicySnapshot? snapshot,
    bool? isOpen,
    bool? isReadOnly,
  }) {
    return NetworkPolicyState(
      snapshot: snapshot ?? this.snapshot,
      isOpen: isOpen ?? this.isOpen,
      isReadOnly: isReadOnly ?? this.isReadOnly,
    );
  }
}

final networkPolicyControllerProvider =
    StateNotifierProvider<NetworkPolicyNotifier, NetworkPolicyState>(
      (ref) => NetworkPolicyNotifier(ref),
    );

/// Policy for the active workspace, for tool gating.
///
/// Absent means closed: nothing leaves the device until the user enables one
/// tool in one workspace.
final activeNetworkPolicyProvider = Provider<NetworkPolicy>((ref) {
  // The active workspace id is read lazily by callers that know it; this
  // provider answers closed so a tool built without a workspace never runs.
  // Concrete call sites read the controller snapshot with their workspace id.
  return NetworkPolicy.closed;
});

class NetworkPolicyNotifier extends StateNotifier<NetworkPolicyState> {
  NetworkPolicyNotifier(this._ref) : super(const NetworkPolicyState()) {
    _open();
  }

  final Ref _ref;

  Future<void> _open() async {
    try {
      final store = await _ref.read(networkPolicyStoreProvider.future);
      state = state.copyWith(
        snapshot: store.load(),
        isOpen: true,
        isReadOnly: store.isReadOnly,
      );
    } catch (_) {
      state = state.copyWith(isOpen: true);
    }
  }

  /// Policy in force for [workspaceId], or closed.
  NetworkPolicy forWorkspace(String workspaceId) =>
      state.snapshot.forWorkspace(workspaceId);

  Future<bool> setWorkspace(String workspaceId, NetworkPolicy policy) async {
    try {
      final store = await _ref.read(networkPolicyStoreProvider.future);
      if (store.isReadOnly) return false;
      final next = state.snapshot.setWorkspace(workspaceId, policy);
      if (!store.save(next)) return false;
      state = state.copyWith(snapshot: next, isReadOnly: store.isReadOnly);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stores the search API key for one workspace plus provider in secure
  /// storage. The policy file keeps only the provider name.
  Future<void> setSearchKey({
    required String workspaceId,
    required String provider,
    required String apiKey,
  }) async {
    final key = webSearchKeyFor(workspaceId, provider);
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await SecureStorage.instance.delete(key);
      return;
    }
    await SecureStorage.instance.writePrimitive(key: key, value: trimmed);
  }

  Future<String?> readSearchKey({
    required String workspaceId,
    required String provider,
  }) {
    return SecureStorage.instance.readPrimitive(
      webSearchKeyFor(workspaceId, provider),
    );
  }

  Future<void> clearSearchKey({
    required String workspaceId,
    required String provider,
  }) {
    return SecureStorage.instance.delete(
      webSearchKeyFor(workspaceId, provider),
    );
  }
}
