import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/widgets/chat_composer.dart';
import 'package:installm/core/widgets/composer_command_picker.dart';

const commands = [
  (command: '/chat', description: 'Ordinary chat'),
  (command: '/review', description: 'Review supplied changes'),
  (command: '/research', description: 'Research a topic'),
];

void main() {
  test(
    'completion only edits the initial slash token and preserves task text',
    () {
      const value = TextEditingValue(
        text: '  /review supplied task',
        selection: TextSelection.collapsed(offset: 5),
      );
      final query = ComposerCommandQuery.atCaret(value, commands)!;
      expect(query.matches.map((c) => c.command), ['/review', '/research']);
      final next = query.insert(value, commands.last);
      expect(next.text, '  /research supplied task');
      expect(next.selection.baseOffset, 11);
      for (final value in [
        const TextEditingValue(
          text: '/review task',
          selection: TextSelection.collapsed(offset: 12),
        ),
        const TextEditingValue(
          text: 'path/to',
          selection: TextSelection.collapsed(offset: 7),
        ),
        const TextEditingValue(
          text: '/',
          selection: TextSelection(baseOffset: 0, extentOffset: 1),
        ),
        const TextEditingValue(
          text: '/r',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      ]) {
        expect(ComposerCommandQuery.atCaret(value, commands), isNull);
      }
    },
  );

  late TextEditingController controller;
  var sent = 0;
  setUp(() {
    controller = TextEditingController();
    sent = 0;
  });
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    List<ComposerCommand> options = commands,
    bool enabled = true,
    double scale = 1,
    Brightness brightness = Brightness.light,
    double keyboard = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              controller: controller,
              enabled: enabled,
              hintText: 'Message',
              commands: options,
              onSend: () async {
                sent++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'floating list filters before send and tapping inserts without sending',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/review'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(ListTile).last).dy,
        lessThan(tester.getTopLeft(find.byType(ChatComposer)).dy),
      );
      await tester.enterText(find.byType(TextField), '/re');
      await tester.pumpAndSettle();
      expect(find.text('/chat'), findsNothing);
      await tester.tap(find.text('/review'));
      await tester.pumpAndSettle();
      expect(controller.text, '/review ');
      expect(find.byType(ListTile), findsNothing);
      expect(sent, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, 1);
    },
  );

  testWidgets(
    'arrows, Tab, Escape and subsequent typing keep normal send behavior',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, '/review ');
      expect(sent, 0);
      await tester.enterText(find.byType(TextField), '/re');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.text, '/review ');
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, 1);
      await tester.enterText(find.byType(TextField), '/res');
      await tester.pumpAndSettle();
      expect(find.text('/research'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '/');
      await tester.pumpAndSettle();
      expect(find.text('/chat'), findsOneWidget);
    },
  );

  testWidgets('losing focus, generation and revoked options hide the list', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '/rev');
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);
    await pump(tester, options: [commands.first]);
    expect(find.text('/review'), findsNothing);
    await pump(tester);
    expect(find.text('/review'), findsOneWidget);
    await pump(tester, enabled: false);
    expect(find.byType(ListTile), findsNothing);
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets(
    'long list fits above keyboard at 320px and 2x text in both themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final options = List.generate(
        16,
        (i) => (
          command: '/command-$i',
          description: 'A useful command with a longer description',
        ),
      );
      for (final brightness in Brightness.values) {
        await pump(
          tester,
          options: options,
          scale: 2,
          brightness: brightness,
          keyboard: 260,
        );
        await tester.enterText(find.byType(TextField), '/');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 15; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        final selected = find.text('/command-15');
        expect(tester.getTopLeft(selected).dy, greaterThanOrEqualTo(0));
        expect(
          tester.getBottomLeft(selected).dy,
          lessThan(tester.getTopLeft(find.byType(ChatComposer)).dy),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(controller.text, '/command-15 ');
      }
    },
  );
}
