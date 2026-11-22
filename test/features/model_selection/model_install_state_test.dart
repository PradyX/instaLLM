import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/domain/model_family.dart';
import 'package:installm/features/model_selection/domain/model_install_state.dart';

/// A library record can outlive its file: a file removed outside the app, a
/// wipe, or a record left by a build that registered a download it never
/// finished. Presenting that record as installed dead-ends the chat, so the
/// library reconciles every record against storage and says "file missing"
/// instead, with the download offered again.
void main() {
  LlmModel record({required bool isDownloaded, String? fileName = 'a.gguf'}) {
    return LlmModel(
      id: 'model-a',
      name: 'Model A',
      parameterSize: '1B',
      description: 'Repository',
      downloadUrl: 'https://huggingface.co/org/repo/resolve/main/a.gguf',
      localFileName: fileName,
      isDownloaded: isDownloaded,
      isCustom: true,
      modelSource: ModelSource.customUrl,
    );
  }

  group('installStateFor', () {
    test('a present file is an installed model', () {
      expect(
        installStateFor(filePresent: true, recordedInstalled: true),
        ModelInstallState.installed,
      );
      expect(
        installStateFor(filePresent: true, recordedInstalled: false),
        ModelInstallState.installed,
      );
    });

    test('a record whose file is gone is a missing file, not an install', () {
      expect(
        installStateFor(filePresent: false, recordedInstalled: true),
        ModelInstallState.missingFile,
      );
    });

    test('a file that was never there is simply not installed', () {
      expect(
        installStateFor(filePresent: false, recordedInstalled: false),
        ModelInstallState.notInstalled,
      );
    });
  });

  group('withVerifiedInstall', () {
    test('a stored install whose file vanished becomes a missing file', () {
      final verified = withVerifiedInstall(
        record(isDownloaded: true),
        filePresent: false,
      );

      expect(verified.isDownloaded, isFalse);
      expect(verified.fileMissing, isTrue);
      // The record is kept whole, so the same download repairs it.
      expect(verified.downloadUrl, contains('a.gguf'));
      expect(verified.localFileName, 'a.gguf');
      expect(verified.name, 'Model A');
    });

    test('an install whose file is present is left installed', () {
      final verified = withVerifiedInstall(
        record(isDownloaded: true),
        filePresent: true,
      );

      expect(verified.isDownloaded, isTrue);
      expect(verified.fileMissing, isFalse);
    });

    test('a never-installed record is not called missing', () {
      final verified = withVerifiedInstall(
        record(isDownloaded: false),
        filePresent: false,
      );

      expect(verified.isDownloaded, isFalse);
      expect(verified.fileMissing, isFalse);
    });

    test('a re-download clears the missing-file state', () {
      final missing = withVerifiedInstall(
        record(isDownloaded: true),
        filePresent: false,
      );
      final repaired = withVerifiedInstall(missing, filePresent: true);

      expect(repaired.isDownloaded, isTrue);
      expect(repaired.fileMissing, isFalse);
    });

    test('a record with no file name is not installed, whatever it says', () {
      final verified = withVerifiedInstall(
        record(isDownloaded: true, fileName: null),
        filePresent: false,
      );

      expect(verified.isDownloaded, isFalse);
      expect(verified.fileMissing, isTrue);
    });
  });

  test('a family reports a missing file so its row can warn', () {
    final family = ModelFamily(
      key: 'model-a',
      displayName: 'Model A',
      capabilities: const [],
      variants: [
        ModelVariant(
          model: withVerifiedInstall(
            record(isDownloaded: true),
            filePresent: false,
          ),
          quantization: 'Q4_K_M',
          quantizationIsRead: false,
          parameterCount: 1,
        ),
      ],
    );

    expect(family.hasMissingFile, isTrue);
    expect(family.hasInstalled, isFalse);
  });
}
