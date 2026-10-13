/// Read-only wire identifiers from releases before the app identity changed.
/// These are required to preserve user exports; new exports use InstaLLM.
abstract final class LegacyExportFormats {
  static const backup = 'pocketllm.backup';
  static const conversations = 'pocketllm.conversations';
  static const personas = 'pocket_llm.personas';
}
