import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/application/companion_transcriber.dart';
import 'package:installm/features/companion/application/companion_turn_runner.dart';
import 'package:installm/features/companion/data/companion_settings_store.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';
import 'package:installm/features/companion/presentation/companion_page.dart';
import 'package:installm/features/model_selection/domain/llm_model.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/voice/application/recording_controller.dart';
import 'package:installm/features/voice/application/tts_controller.dart';
import 'package:installm/features/voice/data/microphone_recorder.dart';
import 'package:installm/features/voice/data/platform_tts_service.dart';
import 'package:installm/features/voice/domain/speech_voice.dart';
import 'package:path/path.dart' as p;

const String _clipPath = '/tmp/installm-companion-clip.wav';

/// A microphone that never touches a device: it answers the permission
/// question, hands back a clip path, and lets the test push levels.
class _FakeRecorder implements MicrophoneRecorder {
  final StreamController<double> _levels = StreamController<double>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  final List<String> deleted = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> start() async {
    startCalls++;
    return _clipPath;
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return _clipPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> deleteRecording(String path) async {
    deleted.add(path);
  }

  @override
  Stream<double> amplitudes({
    Duration interval = const Duration(milliseconds: 60),
  }) => _levels.stream;

  @override
  void dispose() {}

  void emit(double level) => _levels.add(level);
}

class _RefusingRecorder extends _FakeRecorder {
  @override
  Future<bool> requestPermission() async => false;
}

/// Speech model that hears whatever the test says it heard.
class _FakeTranscriber implements CompanionTranscriber {
  _FakeTranscriber({this.heard = 'what is the time', this.failure});

  final String heard;
  final String? failure;
  final List<String> clips = [];

  @override
  Future<String> transcribe(String clipPath) async {
    clips.add(clipPath);
    if (failure != null) throw CompanionTurnException(failure!);
    return heard;
  }
}

/// Model that answers with words the test chooses, or fails the way a missing
/// model does.
class _FakeRunner implements CompanionTurnRunner {
  _FakeRunner({this.reply = 'It is just after nine.', this.failure});

  final String? reply;
  final String? failure;
  final List<String> transcripts = [];
  int interrupts = 0;

  @override
  Future<String?> answer(String transcript) async {
    transcripts.add(transcript);
    if (failure != null) throw CompanionTurnException(failure!);
    return reply;
  }

  @override
  void interrupt() => interrupts++;
}

/// The device voice, recorded instead of heard.
class _FakeSpeechEngine implements SpeechSynthesisEngine {
  final List<String> spoken = [];
  bool stopped = false;

  @override
  Future<void> prepare() async {}

  @override
  Future<List<SpeechVoice>> voices() async => const [];

  @override
  Future<void> speak({
    required String text,
    required double rate,
    SpeechVoice? voice,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

late Directory _tempDir;
late CompanionSettingsStore _store;

/// Settings live on disk, so the tests use a real file in a temp directory:
/// the page then reads exactly what a device would read.
///
/// The directory is created synchronously: a widget test's body runs inside the
/// fake clock, where a real asynchronous file-system future never completes.
void _useSettings({bool enabled = true, String name = 'Ada'}) {
  _tempDir = Directory.systemTemp.createTempSync('companion-page-');
  _store = CompanionSettingsStore(
    File(p.join(_tempDir.path, 'companion', 'settings.json')),
  );
  _store.save(CompanionSettings(name: name, enabled: enabled));
}

/// The orb breathes forever, so the page never settles. Pump a bounded number
/// of frames instead: enough for the settings file and each turn step to land.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 16; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  MicrophoneRecorder recorder, {
  CompanionTranscriber? transcriber,
  CompanionTurnRunner? runner,
  SpeechSynthesisEngine? speech,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        microphoneRecorderProvider.overrideWithValue(recorder),
        companionSettingsStoreProvider.overrideWith((ref) async => _store),
        companionTranscriberProvider.overrideWithValue(
          transcriber ?? _FakeTranscriber(),
        ),
        companionTurnRunnerProvider.overrideWithValue(runner ?? _FakeRunner()),
        speechSynthesisEngineProvider.overrideWithValue(
          speech ?? _FakeSpeechEngine(),
        ),
        chatModelsProvider.overrideWithValue(const <LlmModel>[]),
        selectedChatModelProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(home: CompanionPage()),
    ),
  );
  await _settle(tester);
}

void main() {
  tearDown(() async {
    if (_tempDir.existsSync()) await _tempDir.delete(recursive: true);
  });

  testWidgets('one turn hears, answers, speaks and deletes the clip', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber(heard: 'what is the time');
    final runner = _FakeRunner(reply: 'It is just after nine.');
    final speech = _FakeSpeechEngine();
    await _pumpPage(
      tester,
      recorder,
      transcriber: transcriber,
      runner: runner,
      speech: speech,
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(recorder.startCalls, 0);

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    expect(recorder.startCalls, 1);
    expect(find.text('Listening…'), findsOneWidget);

    // Sustained speech: the page requires a short run of readings above the
    // room before it accepts a capture, so one frame would be a blip.
    recorder.emit(0.05);
    await tester.pump(const Duration(milliseconds: 60));
    for (var reading = 0; reading < 3; reading++) {
      recorder.emit(0.8);
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.text('Listening…'));
    await _settle(tester);

    expect(recorder.stopCalls, 1);
    expect(transcriber.clips, [_clipPath]);
    expect(runner.transcripts, ['what is the time']);
    expect(speech.spoken, ['It is just after nine.']);
    expect(recorder.deleted, [_clipPath]);
    // The answer reopens the microphone by itself, so the next turn needs no
    // tap; the page says so rather than looking stuck.
    expect(find.text('Listening…'), findsOneWidget);

    // The turn stays on the page, faded, and nothing claims it was saved.
    expect(find.text('what is the time'), findsOneWidget);
    expect(find.text('It is just after nine.'), findsOneWidget);
  });

  testWidgets('a pause ends the turn and the answer reopens the microphone', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber(heard: 'tell me a joke');
    final runner = _FakeRunner(reply: 'Only if you promise to laugh.');
    final speech = _FakeSpeechEngine();
    await _pumpPage(
      tester,
      recorder,
      transcriber: transcriber,
      runner: runner,
      speech: speech,
    );

    await tester.tap(find.text('Ready'));
    await _settle(tester);

    // A quiet reading first, so the page learns the room, then speech (three
    // readings, the minimum it counts), then the 1.5 s pause the settings
    // describe, with no tap at all.
    recorder.emit(0.05);
    await tester.pump(const Duration(milliseconds: 60));
    recorder.emit(0.7);
    await tester.pump(const Duration(milliseconds: 60));
    recorder.emit(0.75);
    await tester.pump(const Duration(milliseconds: 60));
    recorder.emit(0.7);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1600));
    await _settle(tester);

    expect(transcriber.clips, [_clipPath]);
    expect(speech.spoken, ['Only if you promise to laugh.']);
    expect(find.text('tell me a joke'), findsOneWidget);

    // Hands-free: the next turn starts by itself, without another tap.
    expect(recorder.startCalls, 2);
    expect(find.text('Listening…'), findsOneWidget);

    // The follow-up nobody spoke into closes itself instead of recording an
    // empty room.
    await tester.pump(const Duration(seconds: 13));
    await _settle(tester);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('an idle page never treats silence as a finished sentence', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber();
    await _pumpPage(tester, recorder, transcriber: transcriber);

    await tester.tap(find.text('Ready'));
    await _settle(tester);

    // Twelve seconds of true silence: the meter reads zero, nothing is said,
    // and the manual capture must stay open rather than inventing a turn.
    await tester.pump(const Duration(seconds: 12));
    await _settle(tester);

    expect(find.text('Listening…'), findsOneWidget);
    expect(transcriber.clips, isEmpty);
    expect(recorder.stopCalls, 0);
  });

  testWidgets('a capture with no speech is never sent to the speech model', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber();
    await _pumpPage(tester, recorder, transcriber: transcriber);

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    await tester.tap(find.text('Listening…'));
    await _settle(tester);

    // Room noise only: transcribing this is what makes a speech model invent
    // "[music]" and the Companion answer itself.
    expect(transcriber.clips, isEmpty);
    expect(find.textContaining('Nothing was heard'), findsOneWidget);
    expect(recorder.deleted, [_clipPath]);
  });

  testWidgets('a silent clip is reported and the next turn still works', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final transcriber = _FakeTranscriber(heard: '');
    final runner = _FakeRunner(reply: 'It is just after nine.');
    final speech = _FakeSpeechEngine();
    await _pumpPage(
      tester,
      recorder,
      transcriber: transcriber,
      runner: runner,
      speech: speech,
    );

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    recorder.emit(0.05);
    await tester.pump(const Duration(milliseconds: 60));
    for (var reading = 0; reading < 3; reading++) {
      recorder.emit(0.8);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Listening…'));
    await _settle(tester);

    expect(find.textContaining('No words were audible'), findsOneWidget);
    expect(speech.spoken, isEmpty);
    expect(runner.transcripts, isEmpty);

    // The loop is still usable: a second capture can produce a real turn.
    await tester.tap(find.text('Ready'));
    await _settle(tester);
    expect(find.text('Listening…'), findsOneWidget);
  });

  testWidgets(
    'a failed transcription is explained and does not wedge the page',
    (tester) async {
      _useSettings();
      final recorder = _FakeRecorder();
      final transcriber = _FakeTranscriber(
        failure:
            'Choose a speech model that can hear audio before transcribing.',
      );
      await _pumpPage(tester, recorder, transcriber: transcriber);

      await tester.tap(find.text('Ready'));
      await _settle(tester);
      recorder.emit(0.05);
      await tester.pump(const Duration(milliseconds: 60));
      for (var reading = 0; reading < 3; reading++) {
        recorder.emit(0.8);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(find.text('Listening…'));
      await _settle(tester);

      expect(find.textContaining('Choose a speech model'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      await tester.tap(find.text('Ready'));
      await _settle(tester);
      expect(find.text('Listening…'), findsOneWidget);
      expect(recorder.startCalls, 2);
    },
  );

  testWidgets('a turn with no model says why instead of going silent', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final runner = _FakeRunner(
      failure:
          'Choose a model with the pill at the top of this page, then '
          'speak again.',
    );
    await _pumpPage(tester, recorder, runner: runner);

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    recorder.emit(0.05);
    await tester.pump(const Duration(milliseconds: 60));
    for (var reading = 0; reading < 3; reading++) {
      recorder.emit(0.8);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Listening…'));
    await _settle(tester);

    expect(find.textContaining('Choose a model'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(recorder.deleted, [_clipPath]);
  });

  testWidgets('leaving the page closes the microphone and drops the turn', (
    tester,
  ) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final speech = _FakeSpeechEngine();
    await _pumpPage(tester, recorder, speech: speech);

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    expect(find.text('Listening…'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await _settle(tester);

    expect(recorder.cancelCalls, 1);
    // Nothing was being spoken, so there is no utterance left running either.
    expect(speech.spoken, isEmpty);
  });

  testWidgets('a refused microphone is reported instead of a silent pill', (
    tester,
  ) async {
    _useSettings();
    final recorder = _RefusingRecorder();
    await _pumpPage(tester, recorder);

    await tester.tap(find.text('Ready'));
    await _settle(tester);

    expect(find.text('Ready'), findsOneWidget);
    expect(recorder.startCalls, 0);
    expect(
      find.textContaining('InstaLLM needs microphone access'),
      findsOneWidget,
    );
  });

  testWidgets('a switched-off Companion keeps the microphone shut', (
    tester,
  ) async {
    _useSettings(enabled: false);
    final recorder = _FakeRecorder();
    await _pumpPage(tester, recorder);

    expect(find.text('The Companion is off'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(recorder.startCalls, 0);

    await tester.tap(find.text('Turn on'));
    await _settle(tester);

    expect(_store.load().enabled, isTrue);
    expect(find.text('Ready'), findsOneWidget);
    expect(recorder.startCalls, 0);
  });

  testWidgets('a long session scrolls while the orb stays put', (tester) async {
    _useSettings();
    final recorder = _FakeRecorder();
    final longAnswer = List.generate(
      48,
      (index) => 'Sentence $index of an answer longer than the whole page.',
    ).join(' ');
    final transcriber = _FakeTranscriber(heard: 'tell me everything in detail');
    final runner = _FakeRunner(reply: longAnswer);
    await _pumpPage(
      tester,
      recorder,
      transcriber: transcriber,
      runner: runner,
      speech: _FakeSpeechEngine(),
    );

    final orb = find.byKey(const Key('companion-orb'));
    final before = tester.getRect(orb);

    await tester.tap(find.text('Ready'));
    await _settle(tester);

    for (var turn = 0; turn < 3; turn++) {
      // The answer's follow-up reopens the microphone, a moment after the
      // speech ends; wait for that rather than assuming a frame count.
      for (
        var frame = 0;
        frame < 60 && find.text('Listening…').evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      recorder.emit(0.05);
      await tester.pump(const Duration(milliseconds: 60));
      for (var reading = 0; reading < 3; reading++) {
        recorder.emit(0.8);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(find.text('Listening…'));
      await _settle(tester);
    }

    expect(runner.transcripts, hasLength(3));

    // The orb keeps its place and stays inside the window, however much the
    // session below it has grown.
    expect(tester.getRect(orb), before);
    expect(before.top, greaterThanOrEqualTo(0));
    expect(
      before.bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio,
      ),
    );

    // The transcript itself still scrolls, all the way back to the oldest turn.
    final session = find.byKey(const Key('companion-session'));
    final history = tester.state<ScrollableState>(
      find.descendant(of: session, matching: find.byType(Scrollable)),
    );
    expect(history.position.maxScrollExtent, greaterThan(0));
    await tester.drag(session, const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(history.position.pixels, lessThan(history.position.maxScrollExtent));
    history.position.jumpTo(0);
    await tester.pump();
    expect(tester.getRect(orb), before);
    expect(
      find.text('tell me everything in detail').hitTestable(),
      findsWidgets,
    );
  });

  testWidgets('the orb stays whole in a short window', (tester) async {
    tester.view.physicalSize = const Size(720, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _useSettings();
    final recorder = _FakeRecorder();
    final longAnswer = List.generate(
      40,
      (index) => 'Sentence $index of an answer that fills the session.',
    ).join(' ');
    await _pumpPage(
      tester,
      recorder,
      transcriber: _FakeTranscriber(heard: 'tell me everything'),
      runner: _FakeRunner(reply: longAnswer),
      speech: _FakeSpeechEngine(),
    );

    await tester.tap(find.text('Ready'));
    await _settle(tester);
    for (var turn = 0; turn < 3; turn++) {
      for (
        var frame = 0;
        frame < 60 && find.text('Listening…').evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      recorder.emit(0.05);
      await tester.pump(const Duration(milliseconds: 60));
      for (var reading = 0; reading < 3; reading++) {
        recorder.emit(0.8);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(find.text('Listening…'));
      await _settle(tester);
    }

    final orb = find.byKey(const Key('companion-orb'));
    final shortWindow = tester.getRect(orb);
    expect(shortWindow.top, greaterThanOrEqualTo(0));
    expect(shortWindow.bottom, lessThanOrEqualTo(560));
    expect(shortWindow.width, closeTo(236, 1));

    final session = find.byKey(const Key('companion-session'));
    final history = tester.state<ScrollableState>(
      find.descendant(of: session, matching: find.byType(Scrollable)),
    );
    expect(history.position.maxScrollExtent, greaterThan(0));
    expect(tester.getSize(session).height, greaterThanOrEqualTo(96));
    history.position.jumpTo(0);
    await tester.pump();
    expect(find.text('tell me everything').hitTestable(), findsWidgets);
  });
}
