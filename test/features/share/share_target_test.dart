import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/features/share/application/share_target_provider.dart';
import 'package:installm/features/share/domain/shared_content_receiver.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

class _FakeReceiver implements SharedContentReceiver {
  bool? applied;

  @override
  Future<SharedPayload?> takeInitial() async => null;

  @override
  void listen(void Function(SharedPayload payload) onPayload) {}

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {
    applied = enabled;
  }

  @override
  Future<bool> returnProcessedText(String text) async => false;

  @override
  Future<bool> isAssistantRoleHeld() async => false;

  @override
  Future<bool> requestAssistantRole() async => false;
}

/// A container whose stored choice is [stored], recording what is written.
ProviderContainer _container(
  _FakeReceiver receiver, {
  required bool? stored,
  List<bool>? written,
}) {
  return ProviderContainer(
    overrides: [
      sharedContentReceiverProvider.overrideWithValue(receiver),
      shareTargetEnabledProvider.overrideWith(
        () => ShareTargetNotifier(
          read: () async => stored,
          write: (enabled) async => written?.add(enabled),
        ),
      ),
    ],
  );
}

void main() {
  test('an untouched install keeps the share target off', () async {
    final receiver = _FakeReceiver();
    final container = _container(receiver, stored: null);
    addTearDown(container.dispose);

    expect(container.read(shareTargetEnabledProvider), isFalse);
    await pumpEventQueue();

    expect(container.read(shareTargetEnabledProvider), isFalse);
    expect(receiver.applied, isFalse);
  });

  test('a stored opt-in is applied to the platform at startup', () async {
    final receiver = _FakeReceiver();
    final container = _container(receiver, stored: true);
    addTearDown(container.dispose);

    container.read(shareTargetEnabledProvider);
    await pumpEventQueue();

    expect(container.read(shareTargetEnabledProvider), isTrue);
    expect(receiver.applied, isTrue);
  });

  test('turning it on stores the choice and switches the target on', () async {
    final receiver = _FakeReceiver();
    final written = <bool>[];
    final container = _container(receiver, stored: null, written: written);
    addTearDown(container.dispose);

    container.read(shareTargetEnabledProvider);
    await pumpEventQueue();

    await container.read(shareTargetEnabledProvider.notifier).setEnabled(true);

    expect(container.read(shareTargetEnabledProvider), isTrue);
    expect(written, [true]);
    expect(receiver.applied, isTrue);

    await container.read(shareTargetEnabledProvider.notifier).setEnabled(false);

    expect(container.read(shareTargetEnabledProvider), isFalse);
    expect(written, [true, false]);
    expect(receiver.applied, isFalse);
  });
}
