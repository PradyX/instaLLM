import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/core/navigation/app_shell.dart';
import 'package:installm/core/navigation/navigation_panel_widgets.dart';
import 'package:installm/features/bots/application/bots_controller.dart';
import 'package:installm/features/bots/domain/bot.dart';
import 'package:installm/features/conversations/domain/conversation.dart';
import 'package:installm/features/group_chat/application/group_chat_controller.dart';
import 'package:installm/features/group_chat/data/group_chat_store.dart';
import 'package:installm/features/group_chat/domain/group_chat.dart';
import 'package:installm/features/workspaces/application/workspaces_controller.dart';
import 'package:installm/features/workspaces/data/workspace_store.dart';
import 'package:installm/features/workspaces/domain/workspace.dart';

class _FakeWorkspaces extends WorkspacesNotifier {
  _FakeWorkspaces(this.value);

  final WorkspacesState value;

  @override
  WorkspacesState build() => value;
}

class _FakeBots extends BotsNotifier {
  _FakeBots(this.value);

  final BotsState value;

  @override
  BotsState build() => value;
}

class _FakeRooms extends GroupChatsNotifier {
  _FakeRooms(this.value);

  final GroupChatsState value;

  @override
  GroupChatsState build() => value;
}

const _workspaceId = 'ws-1';

Workspace _workspace() =>
    Workspace.create(id: _workspaceId, name: 'My workspace');

List<ConversationSummary> _chats(int count) {
  final now = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < count; i++)
      ConversationSummary(
        conversation: Conversation(
          id: 'chat-$i',
          title:
              'A conversation with a deliberately long title that has to be '
              'ellipsised inside the sidebar rather than wrapping ($i)',
          createdAt: now.subtract(Duration(minutes: i)),
          updatedAt: now.subtract(Duration(minutes: i)),
        ),
        messageCount: 3,
        lastMessagePreview: 'Preview $i',
        lastMessageAt: now,
      ),
  ];
}

/// Long list with pinned chats appended after the unpinned ones, so a cap
/// that counted pinned rows against itself would drop them.
List<ConversationSummary> _mixedChats({int pinned = 4, int unpinned = 40}) {
  final now = DateTime(2026, 1, 1);
  return [
    ..._chats(unpinned),
    for (var i = 0; i < pinned; i++)
      ConversationSummary(
        conversation: Conversation(
          id: 'pinned-$i',
          title: 'Pinned chat $i',
          createdAt: now,
          updatedAt: now,
          isPinned: true,
        ),
        messageCount: 1,
        lastMessagePreview: 'Pinned preview $i',
        lastMessageAt: now,
      ),
  ];
}

List<Bot> _bots(int count) => [
  for (var i = 0; i < count; i++)
    Bot.create(
      id: 'bot-$i',
      name: 'Bot number $i with a fairly long name for the sidebar',
      now: DateTime(2026, 1, 1),
    ),
];

List<GroupChat> _rooms(int count) => [
  for (var i = 0; i < count; i++)
    GroupChat.create(
      id: 'room-$i',
      workspaceId: _workspaceId,
      name: 'Room number $i with a long name for the sidebar',
      now: DateTime(2026, 1, 1),
    ),
];

NavigationPanelFixture _fixture({
  int chats = 1,
  int bots = 1,
  int rooms = 1,
  VoidCallback? onCreateBot,
  VoidCallback? onCreateRoom,
}) => NavigationPanelFixture(
  chats: _chats(chats),
  bots: _bots(bots),
  rooms: _rooms(rooms),
  onCreateBot: onCreateBot,
  onCreateRoom: onCreateRoom,
);

Widget _harness({
  required NavigationPanelFixture fixture,
  required AppSection section,
  required Brightness brightness,
  required double width,
  required double height,
  bool drawer = false,
}) {
  final panel = AppNavigationPanel(section: section, fixture: fixture);
  return ProviderScope(
    overrides: [
      workspacesProvider.overrideWith(
        () => _FakeWorkspaces(
          WorkspacesState(
            snapshot: WorkspacesSnapshot(
              workspaces: [_workspace()],
              activeWorkspaceId: _workspaceId,
            ),
            isReady: true,
          ),
        ),
      ),
      botsProvider.overrideWith(
        () =>
            _FakeBots(BotsState(bots: fixture.bots ?? const [], isReady: true)),
      ),
      groupChatsProvider.overrideWith(
        () => _FakeRooms(
          GroupChatsState(
            snapshot: GroupChatsSnapshot(chats: fixture.rooms ?? const []),
            isReady: true,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: brightness,
        ),
      ),
      home: drawer
          ? _DrawerHost(panel: panel, width: width)
          : Scaffold(
              body: SizedBox(width: width, height: height, child: panel),
            ),
    ),
  );
}

class _DrawerHost extends StatefulWidget {
  const _DrawerHost({required this.panel, required this.width});

  final Widget panel;
  final double width;

  @override
  State<_DrawerHost> createState() => _DrawerHostState();
}

class _DrawerHostState extends State<_DrawerHost> {
  final _key = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _key.currentState?.openDrawer();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _key,
    drawer: Drawer(width: widget.width, child: widget.panel),
    body: const SizedBox.shrink(),
  );
}

void _expectNoLayoutFailure(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';
    for (final docked in [true, false]) {
      final layout = docked ? 'docked' : 'drawer';
      final width = docked ? 1141.0 : 700.0;
      final panelWidth = docked ? 280.0 : 280.0;

      testWidgets('$mode $layout empty lists show both tabs and sections', (
        tester,
      ) async {
        await _setSurface(tester, Size(width, 893));
        await tester.pumpWidget(
          _harness(
            fixture: _fixture(chats: 0, bots: 0, rooms: 0),
            section: AppSection.chats,
            brightness: brightness,
            width: panelWidth,
            height: 893,
            drawer: !docked,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Chats'), findsOneWidget);
        expect(find.text('Bots'), findsOneWidget);
        expect(find.text('CHATS'), findsNothing);
        expect(find.text('No conversations yet.'), findsOneWidget);
        expect(find.text('See all'), findsNothing);
        _expectNoLayoutFailure(tester);

        await tester.tap(find.text('Bots'));
        await tester.pumpAndSettle();
        expect(find.text('BOTS'), findsOneWidget);
        expect(find.text('ROOMS'), findsOneWidget);
        expect(find.text('No rooms yet.'), findsOneWidget);
        expect(find.byTooltip('New bot'), findsOneWidget);
        expect(find.byTooltip('New room'), findsOneWidget);
        _expectNoLayoutFailure(tester);
      });

      testWidgets('$mode $layout long lists scroll without overflow', (
        tester,
      ) async {
        await _setSurface(tester, Size(width, 893));
        await tester.pumpWidget(
          _harness(
            fixture: _fixture(chats: 44, bots: 26, rooms: 26),
            section: AppSection.chats,
            brightness: brightness,
            width: panelWidth,
            height: 893,
            drawer: !docked,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CHATS'), findsNothing);
        expect(find.text('See all'), findsOneWidget);
        // 44 chats in the fixture, capped at 30 rows with no pinned chats.
        expect(find.byType(NavigationChatTile), findsNWidgets(30));
        _expectNoLayoutFailure(tester);

        await tester.tap(find.text('Bots'));
        await tester.pumpAndSettle();
        expect(find.text('BOTS'), findsOneWidget);
        expect(find.text('ROOMS'), findsOneWidget);
        _expectNoLayoutFailure(tester);

        final scrollable = find.byType(Scrollable).first;
        await tester.drag(scrollable, const Offset(0, -600));
        await tester.pumpAndSettle();
        _expectNoLayoutFailure(tester);

        await tester.tap(find.text('Chats'));
        await tester.pumpAndSettle();
        _expectNoLayoutFailure(tester);
      });

      testWidgets('$mode $layout add buttons are tappable', (tester) async {
        await _setSurface(tester, Size(width, 893));
        var bots = 0;
        var rooms = 0;
        await tester.pumpWidget(
          _harness(
            fixture: _fixture(
              bots: 2,
              rooms: 2,
              onCreateBot: () => bots++,
              onCreateRoom: () => rooms++,
            ),
            section: AppSection.bots,
            brightness: brightness,
            width: panelWidth,
            height: 893,
            drawer: !docked,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('BOTS'), findsOneWidget);

        await tester.tap(find.byTooltip('New bot'));
        await tester.pumpAndSettle();
        expect(bots, 1);

        await tester.tap(find.byTooltip('New room'));
        await tester.pumpAndSettle();
        expect(rooms, 1);
        _expectNoLayoutFailure(tester);
      });
    }
  }

  testWidgets('pinned chats render on top of the 30-chat cap', (tester) async {
    await _setSurface(tester, const Size(1141, 893));
    final chats = _mixedChats(pinned: 4, unpinned: 40);
    await tester.pumpWidget(
      _harness(
        fixture: NavigationPanelFixture(
          chats: chats,
          bots: _bots(1),
          rooms: [],
        ),
        section: AppSection.chats,
        brightness: Brightness.light,
        width: 280,
        height: 893,
      ),
    );
    await tester.pumpAndSettle();

    // Every pinned chat survives, even though it sits after 40 unpinned ones.
    for (var i = 0; i < 4; i++) {
      expect(find.text('Pinned chat $i'), findsOneWidget);
    }
    // 4 pinned rows plus exactly 30 of the 40 unpinned ones.
    expect(find.byType(NavigationChatTile), findsNWidgets(34));
    expect(find.text('Pinned chat 0'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    _expectNoLayoutFailure(tester);

    // See all sits below the last chat row, not above the list.
    final lastRow = tester.getBottomLeft(find.byType(NavigationChatTile).last);
    final seeAll = tester.getTopLeft(find.text('See all'));
    expect(seeAll.dy, greaterThanOrEqualTo(lastRow.dy));
  });

  testWidgets('drawer auto-switches to the Bots tab when a bot opens', (
    tester,
  ) async {
    await _setSurface(tester, const Size(700, 893));
    final fixture = _fixture(bots: 3, rooms: 3);
    final section = ValueNotifier<AppSection>(AppSection.chats);
    addTearDown(section.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspacesProvider.overrideWith(
            () => _FakeWorkspaces(
              WorkspacesState(
                snapshot: WorkspacesSnapshot(
                  workspaces: [_workspace()],
                  activeWorkspaceId: _workspaceId,
                ),
                isReady: true,
              ),
            ),
          ),
          botsProvider.overrideWith(
            () => _FakeBots(
              BotsState(bots: fixture.bots ?? const [], isReady: true),
            ),
          ),
          groupChatsProvider.overrideWith(
            () => _FakeRooms(
              GroupChatsState(
                snapshot: GroupChatsSnapshot(chats: fixture.rooms ?? const []),
                isReady: true,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<AppSection>(
            valueListenable: section,
            builder: (context, value, _) => _DrawerHost(
              panel: AppNavigationPanel(section: value, fixture: fixture),
              width: 280,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHATS'), findsNothing);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('BOTS'), findsNothing);

    // Opening a bot or room moves the page section, and the drawer follows it.
    section.value = AppSection.rooms;
    await tester.pumpAndSettle();
    expect(find.text('BOTS'), findsOneWidget);
    expect(find.text('ROOMS'), findsOneWidget);
    _expectNoLayoutFailure(tester);
  });
}
