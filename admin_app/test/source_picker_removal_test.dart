import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/stream_source_picker_page.dart';
void main(){
 testWidgets('Admin source picker removes Totalsportek while keeping the supported sources',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:StreamSourcePickerPage()));
  for(final name in ['Soco','YYZB','Fawa','ColaTV','Arena Koora'])expect(find.text(name),findsOneWidget);
  expect(find.text('Totalsportek'),findsNothing);
 });
}
