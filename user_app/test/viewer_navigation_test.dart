import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';

void main() {
  testWidgets('Totalsportek is visible and tappable without scrolling on narrow phones', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar:
      PremiumBottomNav(selectedIndex: 0, onSelected: (index) => selected = index))));
    expect(find.text('Xoilac'), findsNothing);
    expect(find.text('Camel1'), findsNothing);
    for (final label in ['Live', 'Soco', 'YYZB', 'Fawa', 'ColaTV', 'Total\nsportek', 'Channels']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
    }
    await tester.tap(find.text('Total\nsportek'));
    expect(selected, 5);
    await tester.tap(find.text('Channels'));
    expect(selected, 6);
    expect(tester.takeException(), isNull);
  });
}
