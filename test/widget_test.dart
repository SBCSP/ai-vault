import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_vault/main.dart';

void main() {
  testWidgets('App shows lock screen on startup', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AiVaultApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI Vault'), findsOneWidget);
  });
}
