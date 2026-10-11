import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
import 'package:pocket_llm/features/voice/application/tts_controller.dart';
import 'package:pocket_llm/features/voice/application/voice_controller.dart';
import 'package:pocket_llm/features/voice/application/voice_conversation_controller.dart';
import 'package:pocket_llm/features/voice/data/platform_speech_service.dart';
import 'package:pocket_llm/features/voice/domain/speech_voice.dart';
import 'package:pocket_llm/features/voice/presentation/speech_voice_picker.dart';
import 'package:pocket_llm/features/voice/presentation/voice_model_picker.dart';

/// Voice settings, living in Settings since the Voice page went away.
///
/// The composer mic transcribes in place with the engine chosen here; the
/// hands-free conversation loop stays one tap away below.
class VoiceSettingsSection extends ConsumerWidget {
  const VoiceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider);
    final settingsController = ref.read(voiceSettingsProvider.notifier);
    final platformAvailable =
        ref.watch(platformSttAvailableProvider).valueOrNull ?? true;
    final voiceState = ref.watch(voiceControllerProvider);
    final selectedModel = voiceState.selectedOption?.model;
    final tts = ref.watch(ttsControllerProvider);
    final ttsController = ref.read(ttsControllerProvider.notifier);
    final readiness = ref.watch(voiceConversationReadinessProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          RadioGroup<SttEngine>(
            groupValue: settings.sttEngine,
            onChanged: (engine) {
              if (engine != null) settingsController.setSttEngine(engine);
            },
            child: Column(
              children: [
                RadioListTile<SttEngine>(
                  value: SttEngine.localModel,
                  title: const Text('Local speech model'),
                  subtitle: const Text(
                    'Fully offline. Needs a GGUF model with an audio '
                    'projector; audio never leaves this device.',
                  ),
                ),
                RadioListTile<SttEngine>(
                  value: SttEngine.platform,
                  enabled: platformAvailable,
                  title: const Text('Device recognition'),
                  subtitle: Text(
                    platformAvailable
                        ? 'Fast and lightweight, but the OS may process '
                              'audio on the vendor\u2019s servers.'
                        : 'Not available on this platform — the local '
                              'speech model covers it.',
                  ),
                ),
              ],
            ),
          ),
          if (settings.sttEngine == SttEngine.localModel) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Speech model'),
              subtitle: Text(
                selectedModel == null
                    ? 'Choose the model that hears audio'
                    : selectedModel.name,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showVoiceModelPicker(context),
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Read new replies aloud'),
            subtitle: const Text(
              'Reads a reply once, as soon as it finishes. Every reply also '
              'has its own Read aloud action.',
            ),
            value: settings.readRepliesAloud,
            onChanged: (value) => settingsController.setReadRepliesAloud(value),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice'),
            subtitle: Text(tts.voiceLabel),
            trailing: TextButton(
              onPressed: () => showSpeechVoicePicker(context),
              child: const Text('Choose'),
            ),
          ),
          if (tts.selectedVoiceIsMissing)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'That voice is not installed any more; the device default '
                  'is used instead.',
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
            child: Row(
              children: [
                const Expanded(child: Text('Speed')),
                Expanded(
                  flex: 3,
                  child: Slider(
                    value: tts.rate,
                    min: minimumSpeechRate,
                    max: maximumSpeechRate,
                    divisions: 15,
                    label: tts.rate.toStringAsFixed(2),
                    onChanged: ttsController.updateRate,
                    onChangeEnd: (_) => ttsController.storeRate(),
                  ),
                ),
                Text(tts.rate.toStringAsFixed(2)),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.record_voice_over_rounded),
            title: const Text('Voice conversation'),
            subtitle: Text(
              readiness.canStart
                  ? 'Hands-free: speak, hear the answer, speak again'
                  : (readiness.blocker ?? 'Not ready yet'),
            ),
            trailing: FilledButton.tonal(
              onPressed: readiness.canStart
                  ? () => context.push(AppRoutes.voiceConversation)
                  : null,
              child: const Text('Start'),
            ),
          ),
        ],
      ),
    );
  }
}
