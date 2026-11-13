import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/companion/domain/companion_settings.dart';

/// Settings › Companion (Road Map 4, Phase 4.0).
///
/// The name is what the Companion is called on its page, and the pause is how
/// long a silence ends a spoken turn. The wake word was descoped after its
/// spike could not be proven on this machine's microphone, so nothing here
/// promises one.
class CompanionSettingsPage extends ConsumerWidget {
  const CompanionSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionSettingsProvider);
    final notifier = ref.read(companionSettingsProvider.notifier);
    final settings = state.settings;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Companion')),
      body: !state.isReady
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (state.errorMessage != null) ...[
                  Card(
                    color: colors.errorContainer,
                    child: ListTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: colors.onErrorContainer,
                      ),
                      title: Text(
                        state.errorMessage!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: 'Dismiss',
                        icon: const Icon(Icons.close),
                        onPressed: notifier.clearError,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (state.isReadOnly) ...[
                  Card(
                    color: colors.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(
                        'These settings are read-only',
                        style: textTheme.bodyMedium,
                      ),
                      subtitle: const Text(
                        'They were written by a newer version of InstaLLM. '
                        'Nothing will overwrite them in this build.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SwitchListTile(
                    secondary: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Companion'),
                    subtitle: const Text(
                      'When on, the Companion page can open the microphone. '
                      'It only opens while that page is visible, and nothing '
                      'is uploaded.',
                    ),
                    value: settings.enabled,
                    onChanged: state.isReadOnly
                        ? null
                        : (value) {
                            notifier.setEnabled(value);
                          },
                  ),
                ),
                const SizedBox(height: 12),
                _NameCard(settings: settings, readOnly: state.isReadOnly),
                const SizedBox(height: 12),
                _TuningCard(settings: settings, readOnly: state.isReadOnly),
                const SizedBox(height: 16),
                Text(
                  'The Companion answers by voice only: there is no composer '
                  'and no saved conversation. Its model is chosen on the '
                  'Companion page, and every setting here stays on this device.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}

/// The name field with its live wake-phrase preview.
class _NameCard extends ConsumerStatefulWidget {
  const _NameCard({required this.settings, required this.readOnly});

  final CompanionSettings settings;
  final bool readOnly;

  @override
  ConsumerState<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends ConsumerState<_NameCard> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _trimmed => _controller.text.trim();

  Future<void> _save() async {
    final error = CompanionSettings.validateName(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    await ref
        .read(companionSettingsProvider.notifier)
        .setName(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final canSave = CompanionSettings.validateName(_controller.text) == null;
    final warning = CompanionSettings.nameWarning(_controller.text);
    final changed = _trimmed != widget.settings.name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'What the Companion is called. Two to '
              '${CompanionSettings.maxNameLength} characters.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !widget.readOnly,
              maxLength: CompanionSettings.maxNameLength,
              textInputAction: TextInputAction.done,
              autofillHints: const [],
              decoration: InputDecoration(
                labelText: 'Companion name',
                border: const OutlineInputBorder(),
                errorText: _error,
                helperText: warning,
                helperMaxLines: 2,
              ),
              onChanged: (value) {
                setState(() {
                  // Nothing is shown for an empty field: it has just been
                  // cleared to retype, which is not a mistake yet.
                  _error = value.trim().isEmpty
                      ? null
                      : CompanionSettings.validateName(value);
                });
              },
              onSubmitted: (_) => _save(),
            ),
            if (!widget.readOnly)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: canSave && changed ? _save : null,
                  child: const Text('Save name'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How long a silence ends a spoken turn.
///
/// The wake-sensitivity value stays in the stored settings for compatibility
/// with files written while the wake word was planned, but no screen shows it
/// and nothing reads it.
class _TuningCard extends ConsumerWidget {
  const _TuningCard({required this.settings, required this.readOnly});

  final CompanionSettings settings;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    final notifier = ref.read(companionSettingsProvider.notifier);
    final seconds = (settings.silenceTimeout.inMilliseconds / 1000).clamp(
      CompanionSettings.minSilenceTimeout.inMilliseconds / 1000,
      CompanionSettings.maxSilenceTimeout.inMilliseconds / 1000,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pause', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'How long you can pause before the Companion decides you have '
              'finished talking.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            _ValueRow(
              label: 'Pause ends the turn',
              value: '${seconds.toStringAsFixed(1)} s',
            ),
            Slider(
              value: seconds,
              min: CompanionSettings.minSilenceTimeout.inMilliseconds / 1000,
              max: CompanionSettings.maxSilenceTimeout.inMilliseconds / 1000,
              divisions:
                  (CompanionSettings.maxSilenceTimeout.inMilliseconds -
                      CompanionSettings.minSilenceTimeout.inMilliseconds) ~/
                  CompanionSettings.silenceTimeoutStep.inMilliseconds,
              label: '${seconds.toStringAsFixed(1)} s',
              onChanged: readOnly
                  ? null
                  : (value) {
                      notifier.setSilenceTimeout(
                        Duration(milliseconds: (value * 1000).round()),
                      );
                    },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.8 s · quick', style: textTheme.bodySmall),
                Text('3.0 s · patient', style: textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: textTheme.bodyMedium)),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
