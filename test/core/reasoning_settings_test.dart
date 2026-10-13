import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/settings/reasoning_settings_provider.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStore;

  /// The app keeps this choice in secure storage beside its other settings; the
  /// channel stands in for the keychain with a map the test can inspect.
  setUp(() {
    secureStore = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final arguments = (call.arguments as Map).cast<String, Object?>();
            final key = arguments['key'] as String?;
            if (key == null) return null;

            switch (call.method) {
              case 'write':
                secureStore[key] = arguments['value'] as String;
                return null;
              case 'read':
                return secureStore[key];
              case 'delete':
                secureStore.remove(key);
                return null;
              default:
                return null;
            }
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  /// A container whose settings have been created and finished loading, the
  /// way a surface reading them would see them.
  Future<ProviderContainer> launched() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(reasoningSettingsProvider);
    // The notifier loads after it is built, over a platform channel.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return container;
  }

  test('a model nobody has chosen for has no stored state', () async {
    final settings = await launched();

    // Null is what makes the model's own default the state in force: an absent
    // choice is not a choice for "no thinking".
    expect(
      settings.read(reasoningSettingsProvider).choiceFor('qwen-3-0.6b'),
      isNull,
    );
  });

  test('a choice is remembered per model', () async {
    final settings = await launched();

    await settings
        .read(reasoningSettingsProvider.notifier)
        .setChoice('qwen-3-0.6b', ReasoningChoice.thinkingOff);

    expect(
      settings.read(reasoningSettingsProvider).choiceFor('qwen-3-0.6b'),
      ReasoningChoice.thinkingOff,
    );
    // Another model is untouched: the control belongs to the model it was made
    // for, and switching models must not carry it across.
    expect(
      settings.read(reasoningSettingsProvider).choiceFor('qwen-3.5-0.8b'),
      isNull,
    );
    // What is written down is the state's stable id, not its label: labels are
    // wording and wording changes.
    final written = secureStore[ReasoningSettingsNotifier.settingsKey];
    expect(written, contains('qwen-3-0.6b'));
    expect(written, contains('"${ReasoningChoice.thinkingOff.id}"'));
  });

  test('the choice comes back on the next launch', () async {
    final first = await launched();
    await first
        .read(reasoningSettingsProvider.notifier)
        .setChoice('qwen-3-0.6b', ReasoningChoice.thinkingOff);

    final second = await launched();

    expect(
      second.read(reasoningSettingsProvider).choiceFor('qwen-3-0.6b'),
      ReasoningChoice.thinkingOff,
    );
  });

  test('an unreadable or unknown stored value is ignored', () async {
    // A shape from an older or newer build, and a state this version does not
    // know: neither may stop the app from starting, and neither may invent a
    // state the model never declared.
    secureStore[ReasoningSettingsNotifier.settingsKey] =
        '{"choices":{"qwen-3-0.6b":"reasoning-ultra","other":42}}';
    final settings = await launched();

    expect(settings.read(reasoningSettingsProvider).choices, isEmpty);

    // Not even JSON at all.
    secureStore[ReasoningSettingsNotifier.settingsKey] = 'kept for later';
    final other = await launched();

    expect(other.read(reasoningSettingsProvider).choices, isEmpty);
  });
}
