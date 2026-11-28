import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/data/installed_model_metadata.dart';
import 'package:installm/features/model_selection/domain/gguf_metadata.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';

/// A GGUF header with no tensors, just the keys this pass reads.
Uint8List _ggufHeader({required String architecture, String? chatTemplate}) {
  final bytes = BytesBuilder();
  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void string(String value) {
    final encoded = Uint8List.fromList(value.codeUnits);
    u64(encoded.length);
    bytes.add(encoded);
  }

  void kvString(String key, String value) {
    string(key);
    u32(8);
    string(value);
  }

  u32(0x46554747); // "GGUF"
  u32(3);
  u64(0); // tensors
  u64(chatTemplate == null ? 2 : 3);
  kvString('general.architecture', architecture);
  kvString('general.name', 'Fixture');
  if (chatTemplate != null) kvString('tokenizer.chat_template', chatTemplate);
  return bytes.toBytes();
}

LlmModel _model(String path, {GgufMetadata? metadata, bool installed = true}) {
  return LlmModel(
    id: 'fixture',
    name: 'Fixture',
    parameterSize: '1.5B',
    description: 'Test model',
    localFileName: 'fixture.gguf',
    externalPath: path,
    isDownloaded: installed,
    ggufMetadata: metadata,
  );
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('installed-model-metadata');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'an installed file gains the chat template its record never had',
    () async {
      final file = File('${temp.path}/fixture.gguf');
      await file.writeAsBytes(
        _ggufHeader(
          architecture: 'qwen2',
          chatTemplate: '{% if tools %}{{ tools }}{% endif %}',
        ),
      );

      final described = await InstalledModelMetadata().describe([
        _model(file.path),
      ]);

      final metadata = described.single.ggufMetadata;
      expect(metadata, isNotNull);
      expect(metadata!.architecture, 'qwen2');
      expect(
        metadata.supportsToolCalling,
        isTrue,
        reason: 'the template carries a tool protocol',
      );
      expect(
        described.single.supportsToolCalling,
        isTrue,
        reason: 'a downloaded model is offered the tools its file supports',
      );
    },
  );

  test('a record that already carries a header is left alone', () async {
    final file = File('${temp.path}/fixture.gguf');
    await file.writeAsBytes(_ggufHeader(architecture: 'llama'));
    var reads = 0;
    final service = InstalledModelMetadata(
      readHeader: (path) async {
        reads++;
        return _knownMetadata;
      },
    );

    final described = await service.describe([
      _model(file.path, metadata: _knownMetadata),
    ]);

    expect(reads, 0);
    expect(described.single.ggufMetadata, same(_knownMetadata));
  });

  test(
    'an uninstalled model and a missing file are left as they are',
    () async {
      final described = await InstalledModelMetadata().describe([
        _model('${temp.path}/absent.gguf'),
        _model('${temp.path}/other.gguf', installed: false),
      ]);

      expect(described.map((model) => model.ggufMetadata), [null, null]);
    },
  );
}

/// A metadata value for the cases that only need "already known".
const _knownMetadata = GgufMetadata(
  architecture: 'qwen2',
  name: 'Fixture',
  version: 3,
  kvCount: 3,
  tensorCount: 0,
  fileSizeBytes: 1024,
  parameterCount: 1500000000,
  quantization: 'Q4_K_M',
  chatTemplate: '{% if tools %}{{ tools }}{% endif %}',
);
