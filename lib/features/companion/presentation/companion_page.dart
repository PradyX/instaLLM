import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/core/widgets/composer_model_pill.dart';
import 'package:installm/features/companion/application/companion_controller.dart';
import 'package:installm/features/companion/application/companion_settings_controller.dart';
import 'package:installm/features/model_selection/presentation/chat_models_provider.dart';
import 'package:installm/features/model_selection/presentation/model_selection_controller.dart';

/// The Companion: a voice surface, not a chat.
///
/// There is no composer and no message list. The orb and its face hold the
/// middle of the page, this visit's spoken turns fade up beneath it, and the
/// pill at the bottom is the whole control: live input bars, the phase, and
/// start or stop. The microphone runs only while this page is visible, the clip
/// is deleted once its words have been read, and the exchange is never stored.
class CompanionPage extends ConsumerStatefulWidget {
  const CompanionPage({super.key});

  @override
  ConsumerState<CompanionPage> createState() => _CompanionPageState();
}

class _CompanionPageState extends ConsumerState<CompanionPage>
    with WidgetsBindingObserver {
  /// Held because a disposed [ConsumerState] must not read providers, and the
  /// microphone has to be closed even when the page is the thing going away.
  CompanionController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ref.read(companionControllerProvider.notifier);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stopSilently();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The microphone is a foreground tool: leaving the app closes it.
    if (state != AppLifecycleState.resumed) _controller?.stopSilently();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint;
    final listening = ref.watch(
      companionControllerProvider.select((state) => state.isListening),
    );
    final level = ref.watch(
      companionControllerProvider.select((state) => state.levels.last),
    );
    final message = ref.watch(
      companionControllerProvider.select(
        (state) => state.errorMessage ?? state.noticeMessage,
      ),
    );
    final isError = ref.watch(
      companionControllerProvider.select((state) => state.errorMessage != null),
    );
    final phase = ref.watch(
      companionControllerProvider.select((state) => state.phase),
    );
    final exchanges = ref.watch(
      companionControllerProvider.select((state) => state.exchanges),
    );
    final busy = ref.watch(
      companionControllerProvider.select((state) => state.isBusy),
    );
    final models = ref.watch(chatModelsProvider);
    final selected = ref.watch(selectedChatModelProvider);
    final companion = ref.watch(companionSettingsProvider);
    final settingsReady = companion.isReady;
    final companionSettings = companion.settings;

    return AppShell(
      section: AppSection.companion,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Companion'),
              if (settingsReady)
                Text(
                  companionSettings.name,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          leading: isWide
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
          actions: [
            IconButton(
              tooltip: 'Companion settings',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push(AppRoutes.companionSettings),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: ComposerModelPill(
                  models: models,
                  selected: selected,
                  enabled: !listening && !busy,
                  tooltip: 'Companion model',
                  onSelected: (model) => ref
                      .read(modelSelectionControllerProvider.notifier)
                      .selectModel(model),
                  onEmptyPressed: () => context.push(AppRoutes.modelSelection),
                ),
              ),
            ),
          ],
        ),
        drawer: isWide
            ? null
            : const AppNavigationDrawer(section: AppSection.companion),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                child: Column(
                  children: [
                    Expanded(
                      child: _CompanionStage(
                        listening: listening,
                        level: level,
                        phase: phase,
                        exchanges: exchanges,
                      ),
                    ),
                    if (!settingsReady)
                      const _VoicePill(enabled: false)
                    else if (!companionSettings.enabled)
                      _CompanionOffCard(
                        onEnable: () => ref
                            .read(companionSettingsProvider.notifier)
                            .setEnabled(true),
                        onSettings: () =>
                            context.push(AppRoutes.companionSettings),
                      )
                    else
                      const _VoicePill(enabled: true),
                    const SizedBox(height: 10),
                    _StatusLine(message: message, isError: isError),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orb, the face, and the space the spoken turns will fade up into.
class _CompanionStage extends StatelessWidget {
  const _CompanionStage({
    required this.listening,
    required this.level,
    required this.phase,
    required this.exchanges,
  });

  final bool listening;
  final double level;
  final CompanionPhase phase;
  final List<CompanionExchange> exchanges;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A short window scrolls rather than overflows: the orb keeps its size.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  label: 'Companion',
                  value: companionPhaseLabel(phase),
                  child: _CompanionOrb(
                    listening: listening,
                    speaking: phase == CompanionPhase.speaking,
                    level: level,
                  ),
                ),
                const SizedBox(height: 18),
                _SessionHistory(exchanges: exchanges, phase: phase),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The orb: two rings, one glowing core, and a minimal two-dot face.
///
/// The face is its own layer so the companion's Petdex portrait can replace the
/// dots later without touching the page.
class _CompanionOrb extends StatelessWidget {
  const _CompanionOrb({
    required this.listening,
    required this.speaking,
    required this.level,
  });

  final bool listening;
  final bool speaking;
  final double level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = listening || speaking;
    final glow = active ? 0.16 + level * 0.42 : 0.10;
    final highlight = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.32),
      colors.primary,
    );
    final edge = Color.alphaBlend(
      colors.primary.withValues(alpha: 0.5),
      colors.surface,
    );

    return SizedBox(
      width: 236,
      height: 236,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(colors, 232, active ? 0.16 : 0.08),
          _ring(colors, 196, active ? 0.24 : 0.12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.38, -0.42),
                colors: [highlight, colors.primary, edge],
                stops: const [0, 0.52, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: glow),
                  blurRadius: active ? 46 + level * 26 : 36,
                  spreadRadius: active ? 2 + level * 8 : 0,
                ),
              ],
            ),
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -4),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [_Eye(), SizedBox(width: 26), _Eye()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(ColorScheme colors, double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.primary.withValues(alpha: alpha)),
      ),
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF102000).withValues(alpha: 0.58),
      ),
    );
  }
}

/// Where this visit's spoken turns fade up.
///
/// Newest is brightest and older ones dim, so the page reads like something
/// being said rather than a chat to scroll. The turns exist only in memory:
/// leaving the page drops them.
class _SessionHistory extends StatelessWidget {
  const _SessionHistory({required this.exchanges, required this.phase});

  final List<CompanionExchange> exchanges;
  final CompanionPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = colors.onSurfaceVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        children: [
          Text(
            'SESSION',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: muted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          if (exchanges.isEmpty)
            Text(
              _emptyText(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.6,
              ),
            )
          else
            for (var index = 0; index < exchanges.length; index++)
              _ExchangeLines(
                exchange: exchanges[index],
                // The newest turn is the most legible; older ones recede.
                opacity: 0.34 + 0.5 * ((index + 1) / exchanges.length),
              ),
        ],
      ),
    );
  }

  String _emptyText() {
    return switch (phase) {
      CompanionPhase.listening =>
        'Listening. Tap the pill when you are done, and I will answer.',
      CompanionPhase.transcribing => 'Reading back what you said.',
      CompanionPhase.thinking => 'Thinking about it.',
      CompanionPhase.speaking => 'Saying it.',
      CompanionPhase.idle =>
        'Voice only. Tap the pill, speak, and the answer comes back out loud. '
            'Nothing is saved as a chat.',
    };
  }
}

/// One turn: what was heard, then what was said back.
class _ExchangeLines extends StatelessWidget {
  const _ExchangeLines({required this.exchange, required this.opacity});

  final CompanionExchange exchange;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exchange.heard,
            semanticsLabel: 'You said: ${exchange.heard}',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant.withValues(alpha: opacity),
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
          if (exchange.said.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              exchange.said,
              semanticsLabel: 'Companion said: ${exchange.said}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: opacity),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The whole control: live input bars, the state, and start/stop.
class _VoicePill extends ConsumerWidget {
  const _VoicePill({required this.enabled});

  /// False while the settings are still loading or the Companion is off.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(companionControllerProvider);
    final controller = ref.read(companionControllerProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final listening = state.isListening;
    final busy = state.isBusy;

    final VoidCallback? onTap = !enabled
        ? null
        : listening
        ? controller.stop
        : busy
        ? controller.interrupt
        : controller.start;

    final label = enabled ? state.phaseLabel : 'Ready';

    return Semantics(
      button: true,
      label: listening
          ? 'Finish speaking'
          : busy
          ? 'Stop the Companion'
          : 'Talk to the Companion',
      child: Material(
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(
              children: [
                _LevelBars(levels: state.levels, active: listening),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: listening || busy
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (listening)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      _elapsedLabel(state.listeningElapsed),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                _PillControl(listening: listening, busy: busy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How long the microphone has been open, as `0:07`.
String _elapsedLabel(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Each bar is one recent reading: silence leaves them short and dim.
class _LevelBars extends StatelessWidget {
  const _LevelBars({required this.levels, required this.active});

  final List<double> levels;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          for (final level in levels)
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              width: 3,
              height: active ? 6 + level.clamp(0.0, 1.0) * 26 : 5,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.95 : 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// A square in a ring while listening or busy, a microphone when idle.
class _PillControl extends StatelessWidget {
  const _PillControl({required this.listening, required this.busy});

  final bool listening;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: listening || busy ? colors.primary : colors.outline,
          width: 2,
        ),
      ),
      child: Center(
        child: listening || busy
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            : Icon(
                Icons.mic_none_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
      ),
    );
  }
}

/// Shown in place of the pill while the Companion is switched off.
///
/// Turning it on happens here rather than only in Settings, so the page is not
/// a dead end on a fresh install; the name and tuning stay one tap away.
class _CompanionOffCard extends StatelessWidget {
  const _CompanionOffCard({required this.onEnable, required this.onSettings});

  final VoidCallback onEnable;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The Companion is off',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Turn it on to speak here. The microphone opens only while this '
            'page is visible.',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              FilledButton(onPressed: onEnable, child: const Text('Turn on')),
              const SizedBox(width: 4),
              TextButton(onPressed: onSettings, child: const Text('Settings')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message, required this.isError});

  final String? message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text =
        message ??
        'Tap the pill to talk. The microphone closes when you leave this '
            'page, and nothing is saved.';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isError ? colors.error : colors.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }
}
