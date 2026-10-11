import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_llm/core/navigation/app_router.dart';
import 'package:pocket_llm/core/settings/voice_settings_provider.dart';
import 'package:pocket_llm/features/voice/application/tts_controller.dart';
import 'package:pocket_llm/features/voice/application/voice_controller.dart';
import 'package:pocket_llm/features/voice/application/voice_conversation_controller.dart';
import 'package:pocket_llm/features/voice/application/whisper_models_controller.dart';
import 'package:pocket_llm/features/voice/data/platform_speech_service.dart';
import 'package:pocket_llm/features/voice/domain/speech_voice.dart';
import 'package:pocket_llm/features/voice/presentation/speech_voice_picker.dart';
import 'package:pocket_llm/features/voice/presentation/voice_model_picker.dart';
import 'package:pocket_llm/features/voice/presentation/whisper_model_picker.dart';

/// Why the device engine cannot be picked, in the words the settings show.
String _platformLimit(PlatformSpeechStatus? status) {
  if (status == PlatformSpeechStatus.unsupported) {
    return 'This platform has no speech recognizer Pocket LLM can use — the '
        'local speech model covers it.';
  }
  if (status == PlatformSpeechStatus.notAuthorized) {
    return 'Not allowed yet: allow it below, or keep the local model, which '
        'needs no permission.';
  }
  return 'Checking whether this device can recognize speech...';
}

/// Asks macOS for speech recognition.
///
/// This is the one place a permission request is made, and only ever when the
/// user presses it: an app that asks on its own can be aborted by the system
/// when it was launched from a terminal or an IDE, which is where the request
/// gets attributed to the launching process instead of to Pocket LLM.
class _AllowDeviceRecognitionButton extends ConsumerStatefulWidget {
  const _AllowDeviceRecognitionButton();

  @override
  ConsumerState<_AllowDeviceRecognitionButton> createState() =>
      _AllowDeviceRecognitionButtonState();
}

class _AllowDeviceRecognitionButtonState
    extends ConsumerState<_AllowDeviceRecognitionButton> {
  bool _requesting = false;

  Future<void> _ask() async {
    setState(() => _requesting = true);
    final status = await ref
        .read(platformSpeechProvider)
        .requestAuthorization();
    if (!mounted) return;
    setState(() => _requesting = false);
    ref.invalidate(platformSttStatusProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_outcome(status)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _outcome(PlatformSpeechStatus status) {
    return switch (status) {
      PlatformSpeechStatus.ready => 'Device recognition is allowed now.',
      PlatformSpeechStatus.unsupported =>
        'This device has no speech recognizer Pocket LLM can use.',
      PlatformSpeechStatus.notAuthorized =>
        'macOS did not allow speech recognition. The local speech model needs '
            'no permission.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          // macOS credits a first-time request to whatever launched the app,
          // so a build started from a terminal cannot be granted this and is
          // aborted instead of prompted. Saying so is the only warning the app
          // can give before the system takes it down.
          message: Platform.isMacOS
              ? 'macOS only shows this prompt for an app launched from '
                    'Finder or the Dock. Started from a terminal, the app is '
                    'closed instead — allow it there first.'
              : 'Ask the system to let Pocket LLM use its speech recognizer.',
          child: OutlinedButton.icon(
            onPressed: _requesting ? null : _ask,
            icon: _requesting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic_rounded, size: 18),
            label: const Text('Allow device recognition'),
          ),
        ),
      ),
    );
  }
}

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
    final platformStatus = ref.watch(platformSttStatusProvider).valueOrNull;
    final platformAvailable = platformStatus == PlatformSpeechStatus.ready;
    final voiceState = ref.watch(voiceControllerProvider);
    final selectedModel = voiceState.selectedOption?.model;
    final whisperModels = ref.watch(whisperModelsProvider);
    // The chosen Whisper model when it is installed, otherwise what is there:
    // transcription itself falls back the same way, so the row never claims a
    // model that a run would not use.
    final whisperModel =
        whisperModels.installedModel(settings.whisperModelId ?? '') ??
        (whisperModels.installed.isEmpty
            ? null
            : whisperModels.installed.first);
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
                        : _platformLimit(platformStatus),
                  ),
                ),
                RadioListTile<SttEngine>(
                  value: SttEngine.whisper,
                  title: const Text('Whisper'),
                  subtitle: Text(
                    whisperModel == null
                        ? 'Fully offline with a whisper.cpp model. Download '
                              'one from Whisper model below first.'
                        : 'Fully offline, running '
                              '${whisperModel.option.name} '
                              '(${whisperModel.option.sizeLabel}) on this '
                              'device. Audio never leaves it.',
                  ),
                ),
              ],
            ),
          ),
          if (platformStatus == PlatformSpeechStatus.notAuthorized)
            const _AllowDeviceRecognitionButton(),
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
          if (settings.sttEngine == SttEngine.whisper) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const Text('Whisper model'),
              subtitle: Text(
                whisperModel == null
                    ? 'Choose a model to download'
                    : '${whisperModel.option.name} · '
                          '${whisperModel.option.sizeLabel} · '
                          '${whisperModel.option.detail}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showWhisperModelPicker(context),
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
