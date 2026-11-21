import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/highlight_source_service.dart';
import 'package:football_viewer/screens/highlight_source_page.dart';

class FakePublicHighlights extends PublicHighlightsService {
  final offsets=<int>[];
  @override Future<Map<String,dynamic>> request(String action,{int offset=0,String query='',String? entryId,bool force=false})async{
    offsets.add(offset);
    return {'ok':true,'source':'highlights','provider':'dasfootball','has_more':offset==0,'next_offset':offset+12,
      'entries':[for(var i=offset==0?0:10;i<(offset==0?12:15);i++){'id':'highlight-$i','title':'Highlight $i','league':'League'}]};
  }
}
void main(){
  test('public metadata calls contain no Admin JWT or cookies',()async{
    final service=PublicHighlightsService(client:MockClient((request)async{
      expect(request.headers.containsKey('authorization'),isFalse);expect(request.headers.containsKey('cookie'),isFalse);
      expect(request.url.path.endsWith('/highlights'),isTrue);
      return http.Response('{"ok":true,"source":"highlights","provider":"dasfootball","entries":[]}',200);
    }));
    expect((await service.request('catalog'))['entries'],isEmpty);
  });
  testWidgets('scroll loads the next page once, deduplicates and ends the loader',(tester)async{
    final service=FakePublicHighlights();
    await tester.pumpWidget(MaterialApp(home:HighlightsSourcePage(service:service)));await tester.pumpAndSettle();
    expect(service.offsets,[0]);
    await tester.drag(find.byType(ListView),const Offset(0,-1700));await tester.pumpAndSettle();
    expect(service.offsets,[0,12]);expect(find.text('Load more highlights'),findsNothing);
    await tester.drag(find.byType(ListView),const Offset(0,-1200));await tester.pumpAndSettle();
    expect(find.text('Highlight 14'),findsOneWidget);expect(tester.takeException(),isNull);
    await tester.tap(find.byTooltip('Refresh highlights'));await tester.pumpAndSettle();expect(service.offsets.where((i)=>i==0).length,2);
  });
}
