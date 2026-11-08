import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/viewer_navigation.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';
void main(){
 testWidgets('Viewer tabs select Live 2 and each provider in the requested order',(tester)async{
  int? selected;
  await tester.pumpWidget(MaterialApp(home:Scaffold(bottomNavigationBar:PremiumBottomNav(selectedIndex:0,onSelected:(value)=>selected=value))));
  const labels=['Live','Live 2','Soco','YYZB','ColaTV','Fawa','Channels'];
  expect(find.text('Totalsportek'),findsNothing);
  for(var i=0;i<labels.length;i++){
   await tester.tap(find.text(labels[i]));expect(selected,i);
   expect(viewerSourceIndex(viewerSourceAt(i)),i);
   if(i>0)expect(tester.getCenter(find.text(labels[i])).dx,greaterThan(tester.getCenter(find.text(labels[i-1])).dx));
  }
 });
}
