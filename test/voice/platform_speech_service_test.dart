import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_llm/features/voice/data/platform_speech_service.dart';

/// The service is only allowed to *check* permission: asking for it aborts the
/// app when macOS attributes the request to whatever launched it, so a device
/// that has not allowed recognition must never reach the prepare call these
/// tests count.
void main() {
  test('a device that was never allowed is checked, never asked', () async {
    var prepared = false;
    final service = PlatformSpeechService(
      permissionCheck: () async => false,
      prepare: () async {
        prepared = true;
        return true;
      },
    );

    expect(await service.status(), PlatformSpeechStatus.notAuthorized);
    expect(prepared, isFalse);
    expect(await service.listen(), PlatformSpeechStatus.notAuthorized);
    expect(service.isListening, isFalse);
  });

  test('a platform without the plugin reports itself as unsupported', () async {
    var prepared = false;
    final service = PlatformSpeechService(
      permissionCheck: () async => throw MissingPluginException('no plugin'),
      prepare: () async {
        prepared = true;
        return true;
      },
    );

    expect(await service.status(), PlatformSpeechStatus.unsupported);
    expect(prepared, isFalse);
    expect(await service.listen(), PlatformSpeechStatus.unsupported);
  });

  test('an allowed device is prepared once and reported ready', () async {
    var prepares = 0;
    final service = PlatformSpeechService(
      permissionCheck: () async => true,
      prepare: () async {
        prepares++;
        return true;
      },
    );

    expect(await service.status(), PlatformSpeechStatus.ready);
    expect(prepares, 1);

    // The answer is remembered rather than rechecked on every build.
    expect(await service.status(), PlatformSpeechStatus.ready);
    expect(prepares, 1);
  });

  test(
    'an allowed device whose recognizer will not start is not authorized',
    () async {
      final service = PlatformSpeechService(
        permissionCheck: () async => true,
        prepare: () async => false,
      );

      expect(await service.status(), PlatformSpeechStatus.notAuthorized);
    },
  );

  test(
    'a recognizer that throws while starting is not authorized either',
    () async {
      final service = PlatformSpeechService(
        permissionCheck: () async => true,
        prepare: () async => throw StateError('broken'),
      );

      expect(await service.status(), PlatformSpeechStatus.notAuthorized);
    },
  );

  test('asking is what the explicit action does, and only that', () async {
    var prepares = 0;
    final service = PlatformSpeechService(
      permissionCheck: () async => false,
      prepare: () async {
        prepares++;
        return true;
      },
    );

    // Reading the state asks for nothing.
    expect(await service.status(), PlatformSpeechStatus.notAuthorized);
    expect(prepares, 0);

    // The explicit action is the request, and it reports the outcome.
    expect(await service.requestAuthorization(), PlatformSpeechStatus.ready);
    expect(prepares, 1);
  });

  test('a refusal on an explicit ask stays a refusal', () async {
    final service = PlatformSpeechService(
      permissionCheck: () async => false,
      prepare: () async => false,
    );

    expect(
      await service.requestAuthorization(),
      PlatformSpeechStatus.notAuthorized,
    );
  });

  test('asking on a platform without the plugin says unsupported', () async {
    final service = PlatformSpeechService(
      permissionCheck: () async => throw MissingPluginException('no plugin'),
      prepare: () async => throw MissingPluginException('no plugin'),
    );

    expect(
      await service.requestAuthorization(),
      PlatformSpeechStatus.unsupported,
    );
  });
}
