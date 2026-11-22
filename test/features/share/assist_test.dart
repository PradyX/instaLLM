import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/share/application/assist_launch_provider.dart';
import 'package:installm/features/share/application/assistant_role_provider.dart';
import 'package:installm/features/share/application/share_providers.dart';
import 'package:installm/features/share/domain/shared_content_receiver.dart';
import 'package:installm/features/share/domain/shared_payload.dart';

class _FakeReceiver implements SharedContentReceiver {
  _FakeReceiver({this.held = false, this.roleAvailable = true});

  bool held;
  bool roleAvailable;
  int requests = 0;

  @override
  Future<SharedPayload?> takeInitial() async => null;

  @override
  void listen(void Function(SharedPayload payload) onPayload) {}

  @override
  Future<void> setShareTargetEnabled(bool enabled) async {}

  @override
  Future<bool> returnProcessedText(String text) async => false;

  @override
  Future<bool> isAssistantRoleHeld() async => held;

  @override
  Future<bool> requestAssistantRole() async {
    requests++;
    if (!roleAvailable) return false;
    held = true;
    return true;
  }
}

void main() {
  group('an assistant launch', () {
    test('is a payload with nothing in it, so the composer stays empty', () {
      final payload = sharedPayloadFromMap({
        'text': null,
        'attachments': const [],
        'unreadable': 0,
        'assist': true,
      });

      expect(payload, isNotNull);
      expect(payload!.assist, isTrue);
      expect(payload.text, isNull);
      expect(payload.attachments, isEmpty);
      expect(payload.isEmpty, isFalse);
      expect(payload.isProcessText, isFalse);
    });

    test('is not invented from a share, a link or a selection', () {
      final share = sharedPayloadFromMap({'text': 'https://example.com'});
      expect(share!.assist, isFalse);

      final selection = sharedPayloadFromMap({
        'text': 'Selected',
        'processTextReadOnly': false,
      });
      expect(selection!.assist, isFalse);
    });

    test(
      'counts every summon, so a launch is never swallowed by a past one',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(assistLaunchProvider.notifier);

        expect(container.read(assistLaunchProvider), 0);
        notifier.signal();
        expect(container.read(assistLaunchProvider), 1);
        notifier.signal();
        expect(container.read(assistLaunchProvider), 2);
      },
    );
  });

  group('the assistant role', () {
    test('is read from the platform, not assumed', () async {
      final receiver = _FakeReceiver(held: true);
      final container = ProviderContainer(
        overrides: [sharedContentReceiverProvider.overrideWithValue(receiver)],
      );
      addTearDown(container.dispose);

      expect(await container.read(assistantRoleProvider.future), isTrue);
    });

    test(
      'reports unsupported when the platform has no role to grant',
      () async {
        final receiver = _FakeReceiver(roleAvailable: false);
        final container = ProviderContainer(
          overrides: [
            sharedContentReceiverProvider.overrideWithValue(receiver),
          ],
        );
        addTearDown(container.dispose);
        await container.read(assistantRoleProvider.future);

        expect(
          await container.read(assistantRoleProvider.notifier).request(),
          isFalse,
        );
        expect(receiver.requests, 1);
        expect(container.read(assistantRoleProvider).asData?.value, isFalse);
      },
    );

    test('grants it through the platform prompt and reads it back', () async {
      final receiver = _FakeReceiver();
      final container = ProviderContainer(
        overrides: [sharedContentReceiverProvider.overrideWithValue(receiver)],
      );
      addTearDown(container.dispose);
      await container.read(assistantRoleProvider.future);

      expect(
        await container.read(assistantRoleProvider.notifier).request(),
        isTrue,
      );
      expect(container.read(assistantRoleProvider).asData?.value, isTrue);
    });
  });
}
