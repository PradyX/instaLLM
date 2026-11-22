import 'package:installm/features/model_selection/domain/llm_model.dart';

/// What the library can honestly say about a model record.
enum ModelInstallState {
  /// The file is on this device, so the model can be chatted with.
  installed,

  /// The record says installed but the file is gone — removed outside the app,
  /// lost to a wipe, or left by a build that registered a download it never
  /// finished. Saying "installed" here dead-ends the chat, so the library says
  /// what happened and offers the download again.
  missingFile,

  /// Never downloaded, or its download has not finished yet.
  notInstalled,
}

/// The state to show for a record, from the file check and the record's own
/// claim.
///
/// [recordedInstalled] is what the stored record says *before* the check. It is
/// the only thing that tells "its file is gone" apart from "never downloaded",
/// which is why the check must not overwrite it first.
ModelInstallState installStateFor({
  required bool filePresent,
  required bool recordedInstalled,
}) {
  if (filePresent) return ModelInstallState.installed;
  return recordedInstalled
      ? ModelInstallState.missingFile
      : ModelInstallState.notInstalled;
}

/// [model] updated from what storage actually holds.
///
/// A model whose file is gone keeps its record — the download URL, the name,
/// the quantization — and gains [LlmModel.fileMissing] so the library can say
/// so and offer the same download again, instead of presenting a broken
/// install.
LlmModel withVerifiedInstall(LlmModel model, {required bool filePresent}) {
  final state = installStateFor(
    filePresent: filePresent,
    recordedInstalled: model.isDownloaded,
  );
  return model.copyWith(
    isDownloaded: state == ModelInstallState.installed,
    fileMissing: state == ModelInstallState.missingFile,
  );
}
