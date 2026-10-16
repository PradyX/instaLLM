import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/handoff/domain/handoff.dart';

void main() {
  group('HandoffPackage', () {
    test('round-trips history without device paths or weights', () {
      final package = HandoffPackage(
        chatId: 'chat-1',
        title: 'Trip plan',
        exportedAt: DateTime.utc(2026, 10, 16),
        messages: [
          HandoffMessage(role: 'user', text: 'Hello'),
          HandoffMessage(role: 'assistant', text: 'Hi there'),
        ],
        modelId: 'qwen-0.5b',
      );
      final again = HandoffPackage.fromJson(package.toJson());
      expect(again, isNotNull);
      expect(again!.messages, hasLength(2));
      expect(again.toJson().toString(), isNot(contains('/Users')));
      expect(again.toJson().toString(), isNot(contains('.gguf')));
    });

    test('refuses newer versions and empty histories', () {
      expect(
        HandoffPackage.fromJson({
          'version': 999,
          'chatId': 'c',
          'messages': [
            {'role': 'user', 'text': 'hi'},
          ],
        }),
        isNull,
      );
      expect(
        HandoffPackage.fromJson({
          'version': 1,
          'chatId': 'c',
          'messages': const [],
        }),
        isNull,
      );
    });
  });

  group('DeviceProfile', () {
    test('unknown levels fall back, never sync', () {
      final profile = DeviceProfile(modelId: '  ', performanceLevel: 'turbo');
      final normalized = profile.normalized();
      expect(normalized.modelId, isNull);
      expect(normalized.performanceLevel, 'balanced');
      // Local-only by construction: no workspace, no sync keys in the JSON.
      expect(normalized.toJson().toString(), isNot(contains('workspace')));
    });

    test('device choice demonstrably does not sync', () {
      // The profile JSON carries no vault/sync envelope: a test that asserts
      // the absence of sync fields is the device-specificity check.
      final profile = DeviceProfile(modelId: 'smollm-360m');
      final json = profile.toJson();
      expect(json.containsKey('vaultId'), isFalse);
      expect(json.containsKey('syncedAt'), isFalse);
    });
  });

  group('SyncHealth', () {
    test('summary names the problem', () {
      final unreachable = SyncHealth(
        vaultReachable: false,
        conflictCount: 0,
        lastChecked: DateTime.utc(2026, 10, 16),
        detail: 'No such folder.',
      );
      expect(unreachable.isHealthy, isFalse);
      expect(unreachable.summary(), contains('not reachable'));

      final conflicts = SyncHealth(
        vaultReachable: true,
        conflictCount: 2,
        lastChecked: DateTime.utc(2026, 10, 16),
      );
      expect(conflicts.summary(), contains('2 sync conflicts'));
    });
  });
}
