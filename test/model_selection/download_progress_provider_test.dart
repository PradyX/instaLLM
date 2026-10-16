import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/model_selection/presentation/download_progress_provider.dart';

void main() {
  test('progress is per model, keeps an unknown size and clears on demand', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var notifications = 0;
    container.listen(
      downloadProgressProvider,
      (_, _) => notifications++,
      fireImmediately: false,
    );
    final progress = container.read(downloadProgressProvider.notifier);
    Map<String, DownloadProgress> snapshot() =>
        container.read(downloadProgressProvider);

    expect(progress.isDownloading('a'), isFalse);

    // Starting an entry is what makes a card show a download in progress.
    progress.start('a');
    expect(progress.isDownloading('a'), isTrue);
    expect(snapshot()['a']!.total, 0);

    // A response that has not said how large it is keeps the size unknown
    // rather than reporting the bytes so far as the whole file.
    progress.report('a', received: 1024, total: 0);
    expect(snapshot()['a']!.received, 1024);
    expect(snapshot()['a']!.total, 0);

    // The same numbers again are not a change worth rebuilding a card for.
    final identical = notifications;
    progress.report('a', received: 1024, total: 0);
    expect(notifications, identical);

    progress.report('a', received: 2048, total: 4096);
    expect(snapshot()['a']!.progress, closeTo(0.5, 0.0001));

    // One model finishing does not disturb another that is still running.
    progress.start('b');
    progress.clear('a');
    expect(progress.isDownloading('a'), isFalse);
    expect(progress.isDownloading('b'), isTrue);

    progress.clear('b');
    expect(snapshot(), isEmpty);

    final cleared = notifications;
    progress.clear('b');
    expect(notifications, cleared);
    progress.start('a');
    progress.start('a');
    expect(snapshot().length, 1);
  });
}
