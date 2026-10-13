import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/voice/data/platform_speech_service.dart';

/// The service may only *check* permission unless it is asked to ask: reading
/// the state never prepares the recognizer, and the request itself is refused
/// where macOS would answer it by ending the app — an app another program
/// started has the launcher's usage description read instead of its own, and a
/// launcher without one is what took the chat down. The tests count the
/// prepare call to see which of the two happened.
void main() {
  group('RecognizedSpeech', () {
    test('a final transcript wins over the partials before it', () {
      final capture = RecognizedSpeech();
      capture.record('hello', isFinal: false);
      capture.record('hello there', isFinal: false);
      capture.record('Hello, there.', isFinal: true);

      expect(capture.best, 'Hello, there.');
      expect(capture.hasWords, isTrue);
    });

    test('partials alone are still words, because macOS can end a session '
        'without ever finalizing one', () {
      final capture = RecognizedSpeech();
      capture.record('spoken words', isFinal: false);

      expect(capture.best, 'spoken words');
    });

    test('nothing heard is empty, not whitespace', () {
      final capture = RecognizedSpeech();
      capture.record('   ', isFinal: false);

      expect(capture.best, isEmpty);
      expect(capture.hasWords, isFalse);
    });

    test('clearing forgets the session it belonged to', () {
      final capture = RecognizedSpeech();
      capture.record('old words', isFinal: true);
      capture.clear();

      expect(capture.best, isEmpty);
    });
  });

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
      canAsk: () => true,
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
      canAsk: () => true,
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
      canAsk: () => true,
    );

    expect(
      await service.requestAuthorization(),
      PlatformSpeechStatus.unsupported,
    );
  });

  test('a launch the system does not credit is refused, never asked', () async {
    var prepares = 0;
    final service = PlatformSpeechService(
      permissionCheck: () async => false,
      prepare: () async {
        prepares++;
        return true;
      },
      canAsk: () => false,
    );

    // The request is what macOS ends the app for, so nothing may reach the
    // prepare call that would make it. The caller gets the same answer it
    // would have got from a refusal and explains why.
    expect(
      await service.requestAuthorization(),
      PlatformSpeechStatus.notAuthorized,
    );
    expect(prepares, 0);
  });

  test(
    'macOS credits a request to the app only when the system started it',
    () {
      // Finder, the Dock and `open` hand the app to launchd, which is pid 1.
      expect(canOwnSystemPermissionPrompt(parentProcessId: () => 1), isTrue);
      // `flutter run`, a terminal and an IDE keep the app as their own child.
      expect(
        canOwnSystemPermissionPrompt(parentProcessId: () => 31337),
        isFalse,
      );
    },
    skip: Platform.isMacOS
        ? null
        : 'no other platform reads the launcher\'s Info.plist',
  );

  test('every other platform can ask, whatever started the app', () {
    expect(canOwnSystemPermissionPrompt(parentProcessId: () => 31337), isTrue);
  }, skip: Platform.isMacOS ? 'covered above' : null);

  test(
    'the parent process is actually readable',
    () {
      // The rule refuses an unreadable launch, so a lookup that quietly failed
      // would read as "never ask" on every launch.
      expect(systemParentProcessId(), greaterThan(0));
    },
    skip: Platform.isMacOS
        ? null
        : 'libc is read through the macOS system library',
  );
}
