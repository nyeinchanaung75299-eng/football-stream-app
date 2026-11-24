import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/viewer_navigation.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';

void main() {
  testWidgets('compact Viewer navigation preserves all eight original routes',
      (tester) async {
    int? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PremiumBottomNav(
          selectedIndex: 0,
          onSelected: (value) => selected = value,
        ),
      ),
    ));
    const visible = ['Live', 'Live 2', 'Sources', 'Channels', 'HL'];
    for (final label in visible) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Soco'), findsNothing);
    await tester.tap(find.text('Live 2'));
    expect(selected, 1);
    await tester.tap(find.text('Channels'));
    expect(selected, 6);
    await tester.tap(find.text('HL'));
    expect(selected, 7);
    for (final entry in const [
      (label: 'Soco', route: 2),
      (label: 'YYZB', route: 3),
      (label: 'ColaTV', route: 4),
      (label: 'Fawa', route: 5),
    ]) {
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();
      expect(find.text(entry.label), findsOneWidget);
      await tester.tap(find.text(entry.label));
      await tester.pumpAndSettle();
      expect(selected, entry.route);
      expect(viewerSourceIndex(viewerSourceAt(entry.route)), entry.route);
    }
    expect(find.text('Totalsportek'), findsNothing);
  });

  testWidgets('selected provider highlights Sources without hiding other routes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: PremiumBottomNav(
            selectedIndex: 3, onSelected: (_) {}),
      ),
    ));
    expect(find.text('Sources'), findsOneWidget);
    await tester.tap(find.text('Sources'));
    await tester.pumpAndSettle();
    expect(find.text('YYZB'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
