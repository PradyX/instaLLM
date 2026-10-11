import 'package:pocket_llm/features/model_selection/domain/model_compatibility.dart';

/// One file of a speech model, as this app stores it.
///
/// A Whisper model is not a single file: sherpa-onnx runs it as an ONNX
/// encoder/decoder pair plus the token table the decoder emits, so the picker
/// downloads three files and the engine needs all three.
class WhisperModelFile {
  const WhisperModelFile({
    required this.fileName,
    required this.url,
    required this.bytes,
  });

  /// Name the file gets in the app's model directory. It carries the model's
  /// own name, so the three files of a model always travel together and never
  /// collide with another model's.
  final String fileName;

  /// Where the file is downloaded from.
  final String url;

  /// Exact size of the file, used for progress, labels and the completeness
  /// check that tells a finished download apart from a truncated one.
  final int bytes;

  /// Size as text, e.g. `12.3 MB`.
  String get sizeLabel => ModelMemoryEstimate.formatBytes(bytes);
}

/// A Whisper speech model Pocket LLM can run on this device with sherpa-onnx.
///
/// These are the int8 ONNX exports of Whisper that the sherpa-onnx project
/// publishes. They are a different shape from the whisper.cpp GGML files and
/// from the app's own GGUF models — three files per model, and neither of the
/// other formats loads here.
class WhisperModelOption {
  const WhisperModelOption({
    required this.id,
    required this.name,
    required this.detail,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    this.languages = 'Multilingual',
  });

  /// Stable id: what settings store and what the picker keys rows by.
  final String id;

  /// Name the picker shows.
  final String name;

  /// One line about what choosing this model trades off.
  final String detail;

  /// Acoustic model: the audio encoder.
  final WhisperModelFile encoder;

  /// Text decoder that turns encoder output into tokens.
  final WhisperModelFile decoder;

  /// Token table the decoder's output is read against.
  final WhisperModelFile tokens;

  /// What the model understands, for the picker's label.
  final String languages;

  /// Every file the model needs, in the order it is downloaded.
  List<WhisperModelFile> get files => [encoder, decoder, tokens];

  /// Total size of the download.
  int get approximateBytes {
    var total = 0;
    for (final file in files) {
      total += file.bytes;
    }
    return total;
  }

  /// Total size as text, e.g. `103.6 MB`.
  String get sizeLabel => ModelMemoryEstimate.formatBytes(approximateBytes);
}

/// The speech models the picker offers, smallest first.
///
/// Sizes are the real file sizes of the int8 ONNX files on the sherpa-onnx
/// model repositories. Nothing here is fetched on its own: a model is
/// downloaded only when the user presses Download in the picker.
abstract final class WhisperModelCatalog {
  /// Repository the models come from, pinned to the sherpa-onnx models.
  static const String downloadBaseUrl = 'https://huggingface.co/csukuangfj';

  /// The models a user can install, ordered smallest first — which is the
  /// order of the picker and the order transcription falls back in.
  static const List<WhisperModelOption> models = <WhisperModelOption>[
    WhisperModelOption(
      id: 'whisper-tiny',
      name: 'Tiny',
      detail: 'Fastest to run, for short clips and commands.',
      encoder: WhisperModelFile(
        fileName: 'whisper-tiny-encoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-tiny/resolve/main/'
            'tiny-encoder.int8.onnx',
        bytes: 12937772,
      ),
      decoder: WhisperModelFile(
        fileName: 'whisper-tiny-decoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-tiny/resolve/main/'
            'tiny-decoder.int8.onnx',
        bytes: 89855401,
      ),
      tokens: WhisperModelFile(
        fileName: 'whisper-tiny-tokens.txt',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-tiny/resolve/main/'
            'tiny-tokens.txt',
        bytes: 816730,
      ),
    ),
    WhisperModelOption(
      id: 'whisper-base',
      name: 'Base',
      detail: 'A step more accurate, still quick on a laptop or phone.',
      encoder: WhisperModelFile(
        fileName: 'whisper-base-encoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-base/resolve/main/'
            'base-encoder.int8.onnx',
        bytes: 29120534,
      ),
      decoder: WhisperModelFile(
        fileName: 'whisper-base-decoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-base/resolve/main/'
            'base-decoder.int8.onnx',
        bytes: 130672026,
      ),
      tokens: WhisperModelFile(
        fileName: 'whisper-base-tokens.txt',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-base/resolve/main/'
            'base-tokens.txt',
        bytes: 816730,
      ),
    ),
    WhisperModelOption(
      id: 'whisper-small',
      name: 'Small',
      detail: 'Balanced speed and accuracy for everyday dictation.',
      encoder: WhisperModelFile(
        fileName: 'whisper-small-encoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-small/resolve/main/'
            'small-encoder.int8.onnx',
        bytes: 112442483,
      ),
      decoder: WhisperModelFile(
        fileName: 'whisper-small-decoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-small/resolve/main/'
            'small-decoder.int8.onnx',
        bytes: 262226114,
      ),
      tokens: WhisperModelFile(
        fileName: 'whisper-small-tokens.txt',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-small/resolve/main/'
            'small-tokens.txt',
        bytes: 816730,
      ),
    ),
    WhisperModelOption(
      id: 'whisper-turbo',
      name: 'Large v3 Turbo',
      detail: 'Best accuracy, with the speed of a much smaller model.',
      encoder: WhisperModelFile(
        fileName: 'whisper-turbo-encoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-turbo/resolve/main/'
            'turbo-encoder.int8.onnx',
        bytes: 674716297,
      ),
      decoder: WhisperModelFile(
        fileName: 'whisper-turbo-decoder.int8.onnx',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-turbo/resolve/main/'
            'turbo-decoder.int8.onnx',
        bytes: 361080764,
      ),
      tokens: WhisperModelFile(
        fileName: 'whisper-turbo-tokens.txt',
        url:
            '$downloadBaseUrl/sherpa-onnx-whisper-turbo/resolve/main/'
            'turbo-tokens.txt',
        bytes: 816730,
      ),
    ),
  ];

  /// Every file name the catalog owns, which is the set the app is allowed to
  /// delete from its model directory.
  static Set<String> get ownedFileNames => {
    for (final model in models)
      for (final file in model.files) file.fileName,
  };

  /// The model with [id], or null when nothing matches.
  ///
  /// A stored id that no longer names a model (an older build, or a catalog
  /// that changed) resolves to null rather than throwing, so settings written
  /// by another version simply have no Whisper model chosen.
  static WhisperModelOption? byId(String? id) {
    final wanted = id?.trim();
    if (wanted == null || wanted.isEmpty) return null;
    for (final model in models) {
      if (model.id == wanted) return model;
    }
    return null;
  }

  /// The model whose file is [fileName], or null when it is not one of ours.
  static WhisperModelOption? byFileName(String? fileName) {
    final wanted = fileName?.trim();
    if (wanted == null || wanted.isEmpty) return null;
    for (final model in models) {
      for (final file in model.files) {
        if (file.fileName == wanted) return model;
      }
    }
    return null;
  }
}
