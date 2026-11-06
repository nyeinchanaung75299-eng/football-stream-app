import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/sportscore_test_page.dart';

void main() {
  testWidgets('SportScore screen is preview-only until manually loaded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SportScoreTestPage()),
    );

    expect(find.text('SportScore Test Schedule'), findsOneWidget);
    expect(find.textContaining('TESTING ONLY'), findsOneWidget);
    expect(find.text('Load Test Fixtures'), findsOneWidget);
    expect(find.textContaining('Myanmar date:'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Could not load preview'), findsNothing);
  });
}
