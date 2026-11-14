import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/stream_source_picker_page.dart';
void main(){
 testWidgets('Admin source picker restores RoxieStreams and removes Rojadirecta',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:StreamSourcePickerPage()));
  for(final name in ['Soco','YYZB','Fawa','ColaTV','Arena Koora'])expect(find.text(name),findsOneWidget);
  expect(find.text('Totalsportek'),findsNothing);
  await tester.scrollUntilVisible(find.text('RoxieStreams'), 180,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('RoxieStreams'), findsOneWidget);
  expect(find.text('Rojadirecta'), findsNothing);
 });
}
