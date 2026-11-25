import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/viewer_navigation.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';
import 'package:football_viewer/widgets/tab_swipe_region.dart';

void main() {
  testWidgets('eight buttons fit one row at 320px and keep original routes', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int selected = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar:
      PremiumBottomNav(selectedIndex: 0, onSelected: (i) => selected = i))));
    const labels = ['Live','Live 2','Soco','YYZB','ColaTV','Fawa','Channels','HL'];
    final centers = labels.map((label) => tester.getCenter(find.text(label))).toList();
    expect(centers.map((p) => p.dy.round()).toSet().length, 1);
    expect(centers.every((p) => p.dx >= 0 && p.dx <= 320), true);
    for (var i = 0; i < labels.length; i++) {
      await tester.tap(find.text(labels[i]));
      expect(selected, i);
      expect(viewerSourceIndex(viewerSourceAt(i)), i);
    }
    expect(find.text('Sources'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('horizontal swipe selects adjacent tabs and ignores vertical drags', (tester) async {
    int index = 0;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (context, setState) =>
      Scaffold(body: TabSwipeRegion(index:index,count:8,
        onSelected:(i)=>setState(()=>index=i),child: const SizedBox.expand())))));
    await tester.drag(find.byType(TabSwipeRegion), const Offset(-240,0));
    await tester.pumpAndSettle();
    expect(index,1);
    await tester.drag(find.byType(TabSwipeRegion), const Offset(0,-240));
    await tester.pumpAndSettle();
    expect(index,1);
    await tester.drag(find.byType(TabSwipeRegion), const Offset(240,0));
    await tester.pumpAndSettle();
    expect(index,0);
  });
}
