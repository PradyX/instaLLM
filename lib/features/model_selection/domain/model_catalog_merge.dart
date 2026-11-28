import 'package:installm/features/model_selection/domain/llm_model.dart';

/// Combines the records a model list is built from: the catalog this build
/// ships, what Hugging Face discovery found, and what the user added.
///
/// The catalog leads, because its records carry the readable name and the
/// description written for the app; a repository record names the same file
/// after its repository (`Qwen2.5-1.5B-Instruct-GGUF`), which is what the page
/// would show instead.
///
/// Only a quantization is merged: two records are one choice when they name the
/// same file of the same model *from the same publisher*. Comparing the file
/// name alone would collapse publishers — `Qwen/Qwen2.5-1.5B-Instruct-GGUF` and
/// a community re-quantization ship an identically named `Q4_K_M` file, but
/// they are different downloads with different provenance, and the user picks
/// between providers, not just between quantizations. A different file name
/// (another quantization) or another repository is therefore always its own
/// entry.
///
/// The name is compared without regard to case because a record added from a
/// Hugging Face repository keeps the repository's spelling while the catalog
/// writes the same file in lowercase, and both spellings are the one file that
/// repository serves.
///
/// An installed record wins over an uninstalled one for the same file, for the
/// same reason [ModelFamilies] keeps the installed variant: dropping the record
/// of a file that is already on disk would present that file as not installed.
///
/// Discovery is different from an addition the user made, so it is collapsed
/// first: several publishers ship a model under their own repository, which
/// makes one model appear five times in a list that shows a name and a size and
/// nothing else. A discovered record whose file the catalog already offers is
/// dropped, because the app then points at the publisher it calls official, and
/// the rest collapse to one record per model.
List<LlmModel> mergeModelSources({
  required List<LlmModel> catalogModels,
  required List<LlmModel> discoveredModels,
  required List<LlmModel> customModels,
}) {
  final kept = <String, LlmModel>{};
  final order = <String>[];

  void add(LlmModel model) {
    final key = _entryKey(model);
    final existing = kept[key];
    if (existing == null) {
      kept[key] = model;
      order.add(key);
      return;
    }
    if (!existing.isDownloaded && model.isDownloaded) {
      kept[key] = model;
    }
  }

  for (final model in catalogModels) {
    add(model);
  }
  for (final model in _oneRecordPerModel(discoveredModels, catalogModels)) {
    add(model);
  }
  for (final model in customModels) {
    add(model);
  }

  return [for (final key in order) kept[key]!];
}

/// One record per discovered model, whatever the number of publishers.
///
/// A publisher the catalog does not ship is still a republishing of a model the
/// app already offers when it serves the same file: `qwen2.5-0.5b-instruct-q4_k_m.gguf`
/// is that model whichever repository hosts it, so the catalog's own record
/// stands for it and the discovered copy adds nothing but a second row with the
/// same name.
///
/// What is left is collapsed too, because discovery derives a name from the
/// repository without the publisher: `bartowski/...` and `lmstudio-community/...`
/// both arrive as `Qwen2.5 0.5B Instruct`. Two records are the same model when
/// they carry that name and the same parameter size. The installed copy stands
/// for it, and failing that the first, which is the most downloaded because
/// discovery asks for the popular ones first.
List<LlmModel> _oneRecordPerModel(
  List<LlmModel> discovered,
  List<LlmModel> catalog,
) {
  if (discovered.isEmpty) return discovered;

  final catalogFiles = <String>{
    for (final model in catalog)
      if (model.localFileName?.trim().toLowerCase() case final file
          when file != null && file.isNotEmpty)
        file,
  };
  final candidates = [
    for (final model in discovered)
      if (!catalogFiles.contains(model.localFileName?.trim().toLowerCase()))
        model,
  ];
  if (candidates.length < 2) return candidates;

  final kept = <String, LlmModel>{};
  final order = <String>[];
  for (final model in candidates) {
    final key = _modelKey(model);
    final existing = kept[key];
    if (existing == null) {
      kept[key] = model;
      order.add(key);
      continue;
    }
    if (model.isDownloaded && !existing.isDownloaded) {
      kept[key] = model;
    }
  }
  return [for (final key in order) kept[key]!];
}

/// The identity a model is recognised by on screen: its name and its size.
String _modelKey(LlmModel model) {
  final name = model.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$name|${model.parameterSize.trim().toLowerCase()}';
}

/// What identifies one downloadable entry: the publisher's repository and the
/// file inside it.
///
/// A record without a download link has no repository to share, so its own id
/// stands for it.
String _entryKey(LlmModel model) {
  final fileName = model.localFileName?.trim();
  final file = (fileName == null || fileName.isEmpty ? model.id : fileName)
      .toLowerCase();
  final repository = _repositoryOf(model.downloadUrl);
  return repository.isEmpty ? file : '$repository|$file';
}

/// `publisher/repository` from a Hugging Face download URL, lowercased, or an
/// empty string for anything that is not one.
String _repositoryOf(String? url) {
  final uri = Uri.tryParse(url ?? '');
  if (uri == null) return '';
  final segments = uri.pathSegments;
  if (segments.length < 3) return '';
  return '${segments[0]}/${segments[1]}'.toLowerCase();
}
