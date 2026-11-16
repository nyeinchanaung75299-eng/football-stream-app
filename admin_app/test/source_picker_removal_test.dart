import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/stream_source_picker_page.dart';
void main(){
 testWidgets('Admin source picker restores RoxieStreams and removes Rojadirecta',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:StreamSourcePickerPage()));
  for(final name in ['Soco','CricHD','YYZB','Fawa','ColaTV','Arena Koora'])expect(find.text(name),findsOneWidget);
  // CricHD must appear in the initial viewport, not below the fold.
  final socoY = tester.getTopLeft(find.text('Soco')).dy;
  final crichdY = tester.getTopLeft(find.text('CricHD')).dy;
  final yyzbY = tester.getTopLeft(find.text('YYZB')).dy;
  expect(socoY, lessThan(crichdY));
  expect(crichdY, lessThan(yyzbY));
  expect(find.text('Totalsportek'),findsNothing);
  await tester.scrollUntilVisible(find.text('RoxieStreams'), 180,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('RoxieStreams'), findsOneWidget);
  expect(find.text('Rojadirecta'), findsNothing);
  await tester.scrollUntilVisible(find.text('CricHD'), 180,
      scrollable: find.byType(Scrollable).first);
  expect(find.text('CricHD'), findsOneWidget);
 });
}
