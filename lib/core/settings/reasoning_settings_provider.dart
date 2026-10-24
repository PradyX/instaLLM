import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/model_selection/domain/model_reasoning.dart';
import 'package:installm/storage/secure_storage.dart';

/// The reasoning state the user picked, per model.
///
/// Per model rather than global, because the control belongs to the model: a
/// model whose template declares no reasoning has no choice to remember, and
/// switching models must not carry a choice into one that never offered it. An
/// unset model follows its own default, which is what the model does when the
/// prompt says nothing at all.
class ReasoningSettingsState {
  const ReasoningSettingsState({
    this.choices = const <String, ReasoningChoice>{},
  });

  final Map<String, ReasoningChoice> choices;

  /// Null until the user picks something: the model's own default is the
  /// absence of a choice, not a stored one.
  ReasoningChoice? choiceFor(String modelId) => choices[modelId];

  ReasoningSettingsState copyWith({Map<String, ReasoningChoice>? choices}) {
    return ReasoningSettingsState(choices: choices ?? this.choices);
  }
}

final reasoningSettingsProvider =
    NotifierProvider<ReasoningSettingsNotifier, ReasoningSettingsState>(
      ReasoningSettingsNotifier.new,
    );

class ReasoningSettingsNotifier extends Notifier<ReasoningSettingsState> {
  /// Versioned: the stored shape is a map of model id to state id, and a
  /// different shape needs a migration rather than a silent reset.
  static const String settingsKey = 'reasoning_choices_v1';

  @override
  ReasoningSettingsState build() {
    _load();
    return const ReasoningSettingsState();
  }

  Future<void> _load() async {
    try {
      final data = await SecureStorage.instance.read(settingsKey);
      final raw = data?['choices'];
      if (raw is! Map) return;

      final loaded = <String, ReasoningChoice>{};
      for (final entry in raw.entries) {
        final choice = ReasoningChoice.tryParse(entry.value?.toString());
        if (choice == null) continue;
        loaded[entry.key.toString()] = choice;
      }

      state = state.copyWith(choices: loaded);
    } catch (_) {
      // An unreadable file leaves every model on its own default.
    }
  }

  Future<void> setChoice(String modelId, ReasoningChoice choice) async {
    state = state.copyWith(choices: {...state.choices, modelId: choice});
    await _persist();
  }

  Future<void> _persist() async {
    await SecureStorage.instance.write(
      key: settingsKey,
      value: {
        'choices': {
          for (final entry in state.choices.entries) entry.key: entry.value.id,
        },
      },
    );
  }
}
