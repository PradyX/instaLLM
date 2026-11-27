import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:installm/app.dart';
import 'package:go_router/go_router.dart';
import 'package:installm/core/navigation/app_router.dart';
import 'package:installm/core/theme/theme_provider.dart';
import 'package:installm/i18n/strings.g.dart';

/// Drives the real macOS app through the four Play Store desktop screens and
/// writes each one as a 2560x1440 PNG for `scripts/generate_store_art.py`.
///
/// The store captures used to be taken from the window with `screencapture`,
/// which needs a person to navigate the app: the Flutter content exposes no
/// accessibility tree, so driving it meant synthetic clicks, and this
/// repository's agent rules forbid that. A device test drives the app through
/// its own widget tree instead, so each page is reached the way a tap reaches
/// it, and the root repaint boundary is rasterised at 2x — the 2560x1440 the
/// Retina window produced, without the window chrome.
///
/// The app's own data is used: the conversations it has, its installed models
/// and its appearance. Nothing is written to it and no message is sent; only
/// the theme mode is overridden for the run, because the phone and tablet sets
/// are light and the listing reads better when all four agree.
///
/// Run it through `scripts/capture_desktop_screenshots.sh`, which checks
/// signing and refuses a second app instance first.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final root = GlobalKey();

  testWidgets('the desktop store screens', (tester) async {
    tester.view.physicalSize = const Size(2560, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _loadEnvironment();

    await tester.pumpWidget(
      RepaintBoundary(
        key: root,
        child: TranslationProvider(
          child: ProviderScope(
            overrides: [themeModeProvider.overrideWith(_LightThemeMode.new)],
            child: const MyApp(),
          ),
        ),
      ),
    );
    await _settle(tester);

    // 1 — a conversation with a reply in it, as the app opens it.
    await _tap(tester, 'Hey');
    await _settle(tester);
    await _shoot(tester, root, '1.png');

    // 2 — the empty composer with its suggestion cards.
    await _tap(tester, 'New chat');
    await _settle(tester);
    await _shoot(tester, root, '2.png');

    // 3 — the catalog with one installed model's ledger open.
    await _tap(tester, 'Models');
    await _settle(tester, within: const Duration(seconds: 3));
    await _tap(tester, 'SmolLM2-360M-Instruct-GGUF');
    await _settle(tester);
    await _shoot(tester, root, '3.png');

    // 4 — settings, at the top of Appearance.
    await _home(tester);
    await _tap(tester, 'Settings');
    await _settle(tester);
    await _shoot(tester, root, '4.png');
  });
}

/// The app's own theme is whatever the machine was last set to; the store
/// screens are captured light, like the phone and tablet sets.
class _LightThemeMode extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;
}

Future<void> _loadEnvironment() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (error) {
    // Keys the catalog does not need at this point; the pages still render.
    // ignore: avoid_print
    print('dotenv: $error');
  }
  LocaleSettings.useDeviceLocale();
}

/// Pumps for a fixed while instead of waiting to settle: the home page's orb
/// animates forever, so `pumpAndSettle` would time out.
Future<void> _settle(
  WidgetTester tester, {
  Duration within = const Duration(milliseconds: 900),
}) async {
  final deadline = DateTime.now().add(within);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the first control labelled [label], and says so when there is none, so
/// a layout change shows up as a missing page rather than a failed run.
Future<void> _tap(WidgetTester tester, String label) async {
  // Some rows are Text.rich (a name plus a muted suffix), which the plain
  // `find.text` does not match.
  final candidates = [
    find.text(label),
    find.text(label, findRichText: true),
    find.textContaining(label),
  ];
  final target = candidates.firstWhere(
    (finder) => finder.evaluate().isNotEmpty,
    orElse: () => find.text(label),
  );
  if (target.evaluate().isEmpty) {
    // ignore: avoid_print
    print('no control labelled "$label"');
    _dumpTexts(tester);
    return;
  }
  // ignore: avoid_print
  print('tapping "$label"');
  await tester.tap(target.first);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Returns to the home page through the router, so the next capture starts
/// from the same place whichever page was pushed before it.
Future<void> _home(WidgetTester tester) async {
  final context = tester.element(find.byType(Navigator).first);
  GoRouter.of(context).go(AppRoutes.home);
  await tester.pump(const Duration(milliseconds: 600));
}

void _dumpTexts(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((value) => value.isNotEmpty)
      .take(40)
      .toList();
  // ignore: avoid_print
  print('texts: $texts');
}

Future<void> _shoot(WidgetTester tester, GlobalKey root, String name) async {
  await tester.pump();
  final boundary =
      root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('screens/desktop/$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('wrote ${file.path} ${image.width}x${image.height}');
}
