import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/stream_source_picker_page.dart';
void main(){
 testWidgets('Admin source picker keeps RoxieStreams/CricHD but retires LiveXTV and Rojadirecta',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:StreamSourcePickerPage()));
  for(final name in ['Soco','YYZB','Fawa','ColaTV','Arena Koora'])expect(find.text(name),findsOneWidget);
  expect(find.text('Totalsportek'),findsNothing);
  await tester.scrollUntilVisible(find.text('RoxieStreams'), 180,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('RoxieStreams'), findsOneWidget);
  expect(find.text('Rojadirecta'), findsNothing);
  await tester.scrollUntilVisible(find.text('CricHD'), 180,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('CricHD'), findsOneWidget);
  // LiveXTV was retired: it must not appear even after the list is
  // scrolled to the end. Keep CricHD and RoxieStreams available.
  await tester.drag(find.byType(ListView).first, const Offset(0, -500));
  await tester.pumpAndSettle();
  expect(find.text('LiveXTV'), findsNothing);
 });
}
