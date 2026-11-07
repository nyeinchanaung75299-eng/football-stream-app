import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:'https://database.fixture.test',
      publishableKey:'test-public-key',
      httpClient:MockClient((request) async => http.Response('[]',200,
        headers:{'content-type':'application/json'},request:request)),
      authOptions:const FlutterAuthClientOptions(persistSession:false,
        autoRefreshToken:false,detectSessionInUri:false));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token':'local-test-session','refresh_token':'local-test-refresh',
      'token_type':'bearer','user':{'id':'00000000-0000-0000-0000-000000000001',
        'app_metadata':{},'user_metadata':{},'aud':'authenticated',
        'created_at':'2026-10-01T00:00:00Z'},
    }));
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets('Admin keeps all 113 fixtures, finds Spurs and copies full Referer/Origin', (tester) async {
    tester.view.physicalSize=const Size(390,844);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,(call) async {
        if(call.method=='Clipboard.setData') clipboard=(call.arguments as Map)['text'] as String;
        return null;
      });
    addTearDown(()=>tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,null));
    const referer='https://player.fixture.test/player3/channel9?source=published&room=78932';
    const origin='https://player.fixture.test';
    const video='https://video.fixture.test/channel9/index.m3u8?token=full-signed-value';
    var extractions=0;
    Map<String,dynamic> fixture(String home, int minutes) => {
      'source':'totalsportek','source_id':home,'home_team':home,'away_team':'Away',
      'league':'Football','countdown_minutes':minutes,
      'match_time':null,'time_label':'1hr 15m from now','anchors':[],
    };
    final fixtures=[fixture('Bristol City',75),fixture('Clermont',105),
      ...List.generate(110,(i)=>fixture('Club $i',200+i)),
      {...fixture('Leeds United',75),'source_id':'78932','away_team':'Tottenham Hotspur',
        'league':'Premier League','page_url':'https://totalsportekl.is/Leeds-United-vs-Tottenham-Hotspur/78932',
        'anchors':[{'room_num':'78932','nick_name':'Totalsportek'}]},
    ];
    http.Response reply(Object data)=>http.Response(jsonEncode(data),200,
      headers:{'content-type':'application/json'});
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home:SocoImportPage(initialSource:'totalsportek')));
      await tester.pumpAndSettle();
      expect(find.text('113 matches'),findsOneWidget);
      expect(find.text('Available only'),findsNothing);
      for(final query in ['Spurs','စပါး','Leeds']) {
        await tester.enterText(find.byKey(const Key('source-match-search')),query);
        await tester.pumpAndSettle();
        expect(find.text('Leeds United vs Tottenham Hotspur'),findsOneWidget);
        expect(find.text('1 of 113 matches'),findsOneWidget);
      }
      expect(extractions,0);
      await tester.tap(find.textContaining('Totalsportek • UNKNOWN'));
      await tester.pumpAndSettle();
      expect(extractions,1);
      for(final choice in {'Copy Referer':referer,'Copy Origin':origin,'Copy video URL':video,
        'Copy all details':'URL: $video\nReferer: $referer\nOrigin: $origin'}.entries) {
        await tester.tap(find.byTooltip('Copy link or headers'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice.key));
        await tester.pumpAndSettle();
        expect(clipboard,choice.value);
      }
      Navigator.of(tester.element(find.text('Select Stream Quality'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('113 matches'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },()=>MockClient((request) async {
      final body=jsonDecode(request.body) as Map;
      if(request.url.path.endsWith('/soco-links')) {
        if(body['metadata_only']==true) return reply({'source':'totalsportek','metadata_only':true,
          'match_time':DateTime.now().toUtc().add(const Duration(hours:1)).toIso8601String(),'lines':[]});
        extractions++;
        return reply({'source':'totalsportek','lines':[{'label':'Totalsportek • Channel 9',
          'stream_type':'hls','url':video,'referer':referer,'origin':origin,'health_status':'unknown'}]});
      }
      return reply({'source':'totalsportek','matches':fixtures});
    }));
  });
}
