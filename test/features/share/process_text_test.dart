import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/process_text_provider.dart';

void main() {
  test('no request is pending until another app asks for one', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(processTextRequestProvider), isNull);
  });

  test('an editable selection may hand its answer back', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(processTextRequestProvider.notifier).begin(readOnly: false);

    expect(container.read(processTextRequestProvider), isFalse);
  });

  test('a read-only selection is recorded as read-only', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(processTextRequestProvider.notifier).begin(readOnly: true);

    expect(container.read(processTextRequestProvider), isTrue);
  });

  test('clearing forgets the request, so no later answer is handed back', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(processTextRequestProvider.notifier);

    notifier.begin(readOnly: false);
    notifier.clear();

    expect(container.read(processTextRequestProvider), isNull);
  });
}
