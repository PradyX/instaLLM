import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/settings/voice_settings_provider.dart';
import 'package:installm/features/voice/application/tts_controller.dart';
import 'package:installm/features/voice/application/whisper_models_controller.dart';
import 'package:installm/features/voice/data/platform_speech_service.dart';
import 'package:installm/features/voice/domain/speech_voice.dart';
import 'package:installm/features/voice/presentation/speech_voice_picker.dart';
import 'package:installm/features/voice/presentation/whisper_model_picker.dart';

/// Why the device engine cannot be picked, in the words the settings show.
///
/// [canAskFromHere] is false when the system would take the app down for
/// asking rather than prompting — on macOS that is every launch except one the
/// system started itself — so there is no request to offer and the reason says
/// what to do instead.
String _platformLimit(
  PlatformSpeechStatus? status, {
  required bool canAskFromHere,
}) {
  if (status == PlatformSpeechStatus.unsupported) {
    return 'This platform has no speech recognizer InstaLLM can use. '
        'Whisper runs offline on this device.';
  }
  if (status == PlatformSpeechStatus.notAuthorized) {
    if (!canAskFromHere) {
      return 'macOS only shows this prompt to an app it started itself, and '
          'another program started this one. Open InstaLLM from Finder or '
          'the Dock to allow it; Whisper needs no speech-recognition permission.';
    }
    return 'Not allowed yet: allow it below, or use Whisper, which '
        'needs no speech-recognition permission.';
  }
  return 'Checking whether this device can recognize speech...';
}

/// Asks macOS for speech recognition.
///
/// This is the one place a permission request is made, and it is only offered
/// where the system credits this app for the request (see
/// [systemPermissionPromptOwnershipProvider]). Asking from an app that another
/// program started makes macOS read *that program's* usage description and end
/// the app when it has none, which is what used to take the chat down from
/// here; where that is the case, the settings explain it instead of asking.
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
        'This device has no speech recognizer InstaLLM can use.',
      PlatformSpeechStatus.notAuthorized =>
        'macOS did not allow speech recognition. Whisper needs '
            'no speech-recognition permission.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message:
              'Ask the system to let InstaLLM use its speech '
              'recognizer.',
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
/// The composer mic transcribes in place with device recognition or Whisper.
class VoiceSettingsSection extends ConsumerWidget {
  const VoiceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(voiceSettingsProvider);
    final settingsController = ref.read(voiceSettingsProvider.notifier);
    final platformStatus = ref.watch(platformSttStatusProvider).value;
    final platformAvailable = platformStatus == PlatformSpeechStatus.ready;
    // macOS credits a privacy request to the program that started the app, so
    // a launch another program started cannot be granted device recognition.
    final canAskFromHere = ref.watch(systemPermissionPromptOwnershipProvider);
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
                  value: SttEngine.platform,
                  enabled: platformAvailable,
                  title: const Text('Device recognition'),
                  subtitle: Text(
                    platformAvailable
                        ? 'Fast and lightweight, but the OS may process '
                              'audio on the vendor\u2019s servers.'
                        : _platformLimit(
                            platformStatus,
                            canAskFromHere: canAskFromHere,
                          ),
                  ),
                ),
                RadioListTile<SttEngine>(
                  value: SttEngine.whisper,
                  title: const Text('Whisper'),
                  subtitle: Text(
                    whisperModel == null
                        ? 'Fully offline with a Whisper model. Download '
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
          if (platformStatus == PlatformSpeechStatus.notAuthorized &&
              canAskFromHere)
            const _AllowDeviceRecognitionButton(),
          if (settings.sttEngine == SttEngine.whisper) ...[
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
          SwitchListTile(
            title: const Text('Read new replies aloud'),
            subtitle: const Text(
              'Reads a reply once, as soon as it finishes. Every reply also '
              'has its own Read aloud action.',
            ),
            value: settings.readRepliesAloud,
            onChanged: (value) => settingsController.setReadRepliesAloud(value),
          ),
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
        ],
      ),
    );
  }
}
