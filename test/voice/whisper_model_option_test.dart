import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/voice/domain/whisper_model_option.dart';

void main() {
  test('offers models with unique ids and file names', () {
    final ids = <String>{};
    for (final model in WhisperModelCatalog.models) {
      expect(ids.add(model.id), isTrue, reason: model.id);
      expect(model.name, isNotEmpty);
      expect(model.detail, isNotEmpty);
      expect(model.languages, isNotEmpty);
    }
    expect(WhisperModelCatalog.models, isNotEmpty);

    // Every file of every model is named once, so two models can never share
    // (and therefore overwrite or delete) a file.
    final fileNames = <String>[];
    for (final model in WhisperModelCatalog.models) {
      for (final file in model.files) {
        fileNames.add(file.fileName);
      }
    }
    expect(fileNames.toSet().length, fileNames.length);
    expect(WhisperModelCatalog.ownedFileNames, fileNames.toSet());
  });

  test('every model is an encoder, a decoder and a token table', () {
    for (final model in WhisperModelCatalog.models) {
      expect(model.files, hasLength(3));
      expect(model.encoder.fileName, endsWith('-encoder.int8.onnx'));
      expect(model.decoder.fileName, endsWith('-decoder.int8.onnx'));
      expect(model.tokens.fileName, endsWith('-tokens.txt'));

      for (final file in model.files) {
        expect(file.url, startsWith(WhisperModelCatalog.downloadBaseUrl));
        expect(
          file.url,
          contains(model.id.replaceFirst('whisper-', 'sherpa-onnx-whisper-')),
        );
        expect(file.bytes, greaterThan(0));
      }
    }
  });

  test('a model is the size of its files together', () {
    for (final model in WhisperModelCatalog.models) {
      final sum = model.files.fold<int>(0, (total, file) => total + file.bytes);
      expect(model.approximateBytes, sum);
      expect(model.sizeLabel, isNotEmpty);
    }
  });

  test('sizes are real model files, listed smallest first', () {
    var previous = 0;
    for (final model in WhisperModelCatalog.models) {
      // A file below this is a stub, not a model: the service refuses to treat
      // such a file as installed, so the catalog must not advertise it.
      expect(
        model.approximateBytes,
        greaterThan(1024 * 1024),
        reason: model.id,
      );
      expect(model.approximateBytes, greaterThan(previous), reason: model.id);
      previous = model.approximateBytes;
    }
  });

  test('the smallest model is the one called tiny', () {
    expect(WhisperModelCatalog.models.first.id, 'whisper-tiny');
    expect(WhisperModelCatalog.models.first.sizeLabel, endsWith('MB'));
  });

  test('byId finds a stored model and ignores anything else', () {
    final model = WhisperModelCatalog.models.first;
    expect(WhisperModelCatalog.byId(model.id)?.id, model.id);
    expect(WhisperModelCatalog.byId('  ${model.id}  ')?.id, model.id);
    expect(WhisperModelCatalog.byId('tiny.en'), isNull);
    expect(WhisperModelCatalog.byId(''), isNull);
    expect(WhisperModelCatalog.byId(null), isNull);
  });

  test('byFileName maps a file back to the model it belongs to', () {
    final model = WhisperModelCatalog.models[2];
    for (final file in model.files) {
      expect(WhisperModelCatalog.byFileName(file.fileName)?.id, model.id);
    }
    expect(WhisperModelCatalog.byFileName('ggml-large-v3.bin'), isNull);
    expect(WhisperModelCatalog.byFileName('   '), isNull);
    expect(WhisperModelCatalog.byFileName(null), isNull);
  });
}
