import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/agents/application/run_commands.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/core/widgets/composer_command_picker.dart';
import 'package:installm/features/group_chat/presentation/room_mention_composer.dart';
import 'package:installm/features/profile_images/application/profile_images_controller.dart';
import 'package:installm/features/profile_images/data/petdex_service.dart';

void main() {
  final coder = Bot.create(id: 'c', name: 'Coder');
  final planner = Bot.create(id: 'p', name: 'Project Planner');
  final members = [coder, planner];
  late Directory directory;
  late PetdexService portraits;
  late TextEditingController controller;
  var sent = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('room_mentions');
    portraits = PetdexService(directory: directory, dio: Dio());
    controller = TextEditingController();
    sent = 0;
  });
  tearDown(() async {
    controller.dispose();
    portraits.close();
    await directory.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    double scale = 1,
    List<ComposerCommand> commands = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [petdexServiceProvider.overrideWith((_) async => portraits)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: RoomMentionComposer(
                controller: controller,
                members: members,
                commands: commands,
                enabled: true,
                hintText: 'Room',
                onSend: () async {
                  sent++;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'member suggestions filter and mouse selection keeps text around the caret',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'Ask @pro to review');
      controller.selection = const TextSelection.collapsed(offset: 8);
      await tester.pumpAndSettle();
      expect(find.text('@Project Planner'), findsOneWidget);
      expect(find.text('@Coder'), findsNothing);
      await tester.tap(find.text('@Project Planner'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Ask @Project Planner to review');
      expect(controller.selection.baseOffset, 20);
      expect(sent, 0);
      expect(find.byKey(const ValueKey('mention-p')), findsNothing);
    },
  );

  testWidgets(
    'arrows and Return select without sending; Escape restores normal Return',
    (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '@');
      await tester.pumpAndSettle();
      expect(find.text('@Coder'), findsOneWidget);
      expect(find.text('@Project Planner'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.text, '@Project Planner ');
      expect(sent, 0);
      await tester.enterText(find.byType(TextField), '@co');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('@Coder'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, 1);
    },
  );

  testWidgets(
    'suggestions fit a narrow window with large text and support Tab',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, scale: 2);
      await tester.enterText(find.byType(TextField), '@project p');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(controller.text, '@Project Planner ');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the picker offers the commands a room can type', (tester) async {
    await pump(
      tester,
      commands: [
        RewindCommand.option(),
        ...BackgroundCommand.options(),
        ReviewCommand.option(),
      ],
    );
    await tester.enterText(find.byType(TextField), '/rev');
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);

    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();
    expect(controller.text, '/review ');
    expect(sent, 0);

    await tester.enterText(find.byType(TextField), '/rew');
    await tester.pumpAndSettle();
    expect(find.text('/rewind'), findsOneWidget);
  });

  test(
    'ignores emails, selections and unknown names; replaces mid-handle and full spaced names',
    () {
      TextEditingValue value(String text, int caret) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
      expect(BotMentionQuery.atCaret(value('x@co', 4), members), isNull);
      expect(BotMentionQuery.atCaret(value('@outsider', 9), members), isNull);
      final partial = value('Hi @coder, thanks', 6);
      expect(
        BotMentionQuery.atCaret(partial, members)!.insert(partial, coder).text,
        'Hi @Coder, thanks',
      );
      final spaced = value('@Project Planner please', 10);
      expect(
        BotMentionQuery.atCaret(spaced, members)!.insert(spaced, planner).text,
        '@Project Planner please',
      );
    },
  );
}
