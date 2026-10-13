import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/home/presentation/composer_attach_button.dart';

Widget _host({
  bool enabled = true,
  bool canAttachImage = true,
  bool hasHistoryImages = false,
  VoidCallback? onPickImage,
  VoidCallback? onPickHistory,
  VoidCallback? onAttachFiles,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: ComposerAttachButton(
          enabled: enabled,
          canAttachImage: canAttachImage,
          hasHistoryImages: hasHistoryImages,
          onPickImage: onPickImage ?? () {},
          onPickHistory: onPickHistory ?? () {},
          onAttachFiles: onAttachFiles ?? () {},
        ),
      ),
    ),
  );
}

/// The menu entry that carries [label].
PopupMenuItem<String> _itemFor(WidgetTester tester, String label) {
  return tester.widget<PopupMenuItem<String>>(
    find.ancestor(
      of: find.text(label),
      matching: find.byType(PopupMenuItem<String>),
    ),
  );
}

void main() {
  testWidgets('tapping the paperclip opens the attachment menu', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Upload images'), findsOneWidget);
    expect(find.text('Attach files or folder'), findsOneWidget);
  });

  testWidgets('the menu has no persona entry', (tester) async {
    await tester.pumpWidget(_host(hasHistoryImages: true));

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('Persona'), findsNothing);
  });

  testWidgets('Upload images picks an image on a vision model', (tester) async {
    var picked = 0;
    await tester.pumpWidget(_host(onPickImage: () => picked++));

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();
    expect(_itemFor(tester, 'Upload images').enabled, isTrue);
    await tester.tap(find.text('Upload images'));
    await tester.pumpAndSettle();

    expect(picked, 1);
  });

  testWidgets('without vision the image row is greyed out, not relabelled', (
    tester,
  ) async {
    var picked = 0;
    await tester.pumpWidget(
      _host(canAttachImage: false, onPickImage: () => picked++),
    );

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    // The plain label stays; the greyed-out state carries the meaning.
    expect(find.text('Upload images'), findsOneWidget);
    expect(find.textContaining('needs vision'), findsNothing);
    expect(_itemFor(tester, 'Upload images').enabled, isFalse);

    await tester.tap(find.text('Upload images'));
    await tester.pumpAndSettle();

    expect(picked, 0);
  });

  testWidgets('without vision the history row is greyed out too', (
    tester,
  ) async {
    var history = 0;
    await tester.pumpWidget(
      _host(
        canAttachImage: false,
        hasHistoryImages: true,
        onPickHistory: () => history++,
      ),
    );

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Images from this chat'), findsOneWidget);
    expect(find.textContaining('needs a vision model'), findsNothing);
    expect(_itemFor(tester, 'Images from this chat').enabled, isFalse);

    await tester.tap(find.text('Images from this chat'));
    await tester.pumpAndSettle();

    expect(history, 0);
  });

  testWidgets('history and files rows report their own selections', (
    tester,
  ) async {
    var history = 0;
    var files = 0;
    await tester.pumpWidget(
      _host(
        hasHistoryImages: true,
        onPickHistory: () => history++,
        onAttachFiles: () => files++,
      ),
    );

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Images from this chat'));
    await tester.pumpAndSettle();
    expect(history, 1);

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach files or folder'));
    await tester.pumpAndSettle();
    expect(files, 1);
  });

  testWidgets('a disabled composer does not open the menu', (tester) async {
    await tester.pumpWidget(_host(enabled: false));

    await tester.tap(find.byIcon(Icons.attach_file_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Upload images'), findsNothing);
  });
}
