import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/source_player_page.dart';

void main() {
  testWidgets('restricted player requires explicit tap before loading',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SourcePlayerPage(sourcePage: 'https://example.org/embed/live'),
    ));
    expect(find.text('Pop-up Restricted Player'), findsOneWidget);
    expect(find.text('Load Restricted Player'), findsOneWidget);
    expect(find.textContaining('does not block every'), findsOneWidget);
    await tester.tap(find.byKey(const Key('load-sandboxed-player')));
    await tester.pump();
    expect(find.text('Load Restricted Player'), findsNothing);
    // The widget test/native implementation is a safe explanatory fallback.
    expect(find.textContaining('available in NCA Admin Web'), findsOneWidget);
  });

  testWidgets('unsafe page URL never loads in an iframe', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SourcePlayerPage(sourcePage: 'javascript:alert(1)'),
    ));
    expect(find.text('Invalid source website URL.'), findsOneWidget);
    expect(find.byKey(const Key('load-sandboxed-player')), findsNothing);
  });
}
