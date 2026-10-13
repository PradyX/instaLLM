import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:installm/app.dart';
import 'package:installm/i18n/strings.g.dart';

void main() {
  testWidgets('renders the InstaLLM home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      TranslationProvider(child: const ProviderScope(child: MyApp())),
    );

    await tester.pump();

    // The cleared toolbar carries no model picker; with no downloaded
    // models the home screen shows the onboarding empty state.
    expect(find.text('No models ready'), findsOneWidget);
  });
}
