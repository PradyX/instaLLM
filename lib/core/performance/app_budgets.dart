/// Published budgets (Road Map 3 Phase 3.9).
///
/// Measurements, not hopes: startup and large-vault indexing stay within
/// these on the reference devices, and new screens land with their
/// accessibility pass (labels, contrast, text scaling to 2x).
abstract final class AppBudgets {
  /// Cold start to an interactive home on a mid-range Android phone.
  static const Duration startup = Duration(seconds: 4);

  /// Indexing throughput floor for text documents on the same class.
  static const int indexingDocsPerSecond = 4;

  /// Largest vault the budgets are measured against.
  static const int referenceVaultFiles = 5000;

  /// Longest a retrieval preview may take before it shows progress.
  static const Duration retrievalPreview = Duration(milliseconds: 800);
}
