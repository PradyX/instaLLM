import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/github_star/star_prompt.dart';
import 'package:installm/core/github_star/star_prompt_store.dart';

/// The reminder is a one-time ask: every answer, including a dismissal, has to
/// silence it across launches.
void main() {
  late Directory temp;
  late String path;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('installm_star_prompt');
    path = '${temp.path}/star_prompt/state.json';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// A controller reading the same file a later launch would read.
  StarPromptController reloaded() =>
      StarPromptController(StarPromptStore(File(path)));

  test('a fresh install is asked once', () {
    final controller = reloaded();
    expect(controller.isDue, isTrue);
    expect(controller.hasBeenSeen, isFalse);
  });

  test('dismissing the reminder never asks again', () {
    final controller = reloaded();
    controller.recordShown();
    controller.recordAnswer();

    final later = reloaded();
    expect(later.isDue, isFalse);
    // The dot on the Settings row still says the ask was seen.
    expect(later.hasBeenSeen, isTrue);
  });

  test('starring also ends the reminder', () {
    final controller = reloaded();
    controller.recordShown();
    controller.recordAnswer();

    expect(reloaded().isDue, isFalse);
  });

  test('seeing the dialog without answering does not end it', () {
    final controller = reloaded();
    controller.recordShown();

    final later = reloaded();
    expect(later.isDue, isTrue);
    expect(later.hasBeenSeen, isTrue);
  });

  test('a corrupt file reads as a fresh install instead of crashing', () {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{not json');

    final controller = reloaded();
    expect(controller.isDue, isTrue);
    expect(controller.hasBeenSeen, isFalse);

    // Answering still writes, and the damaged file is copied aside first.
    controller.recordShown();
    controller.recordAnswer();
    expect(reloaded().isDue, isFalse);
  });

  test('a file from a newer build is left untouched', () {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"version": 9, "shownCount": 1}');
    final before = File(path).readAsStringSync();

    final controller = reloaded();
    // Nothing was learned from it, so the reminder still counts as unanswered.
    expect(controller.isDue, isTrue);
    expect(controller.isReadOnly, isTrue);
    // The answer is refused rather than downgrading the newer file in place.
    controller.recordAnswer();
    expect(File(path).readAsStringSync(), before);
  });
}
