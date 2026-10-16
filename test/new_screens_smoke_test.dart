import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/features/connections/presentation/connections_page.dart';
import 'package:installm/features/documents/presentation/knowledge_collections_page.dart';
import 'package:installm/features/reminders/presentation/reminders_page.dart';

Future<void> _mockChannels() async {
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secure, (_) async => null);
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return '/tmp/new-screens-smoke';
        }
        return null;
      });
}

Widget _app(Widget child) {
  return ProviderScope(child: MaterialApp(home: child));
}

void main() {
  setUp(_mockChannels);

  testWidgets('Knowledge page renders', (tester) async {
    await tester.pumpWidget(_app(const KnowledgeCollectionsPage()));
    await tester.pump();
    expect(find.text('Knowledge'), findsWidgets);
  });

  testWidgets('Reminders page renders', (tester) async {
    await tester.pumpWidget(_app(const RemindersPage()));
    await tester.pump();
    expect(find.text('Reminders'), findsWidgets);
  });

  testWidgets('Connections page renders', (tester) async {
    await tester.pumpWidget(_app(const ConnectionsPage()));
    await tester.pump();
    expect(find.text('Connections'), findsWidgets);
  });
}
