import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/connected_channels_page.dart';
import 'package:football_admin/services/gateway_request.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url:'https://database.fixture.test',publishableKey:'fixture-public',
      httpClient:MockClient((request) async=>http.Response('[]',200,headers:{'content-type':'application/json'},request:request)),
      authOptions:const FlutterAuthClientOptions(persistSession:false,autoRefreshToken:false,detectSessionInUri:false));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token':'fixture-session','refresh_token':'fixture-refresh','token_type':'bearer',
      'user':{'id':'00000000-0000-4000-8000-000000000001','app_metadata':{},'user_metadata':{},
        'aud':'authenticated','created_at':'2026-10-01T00:00:00Z'},
    }));
  });
  tearDownAll(() async=>Supabase.instance.dispose());
  test('only source catalog reads can be replayed after a route timeout', () {
    expect(GatewayRequest.canRetry('channel-source-sync',{'action':'catalog'}),isTrue);
    expect(GatewayRequest.canRetry('channel-source-sync',{'action':'details'}),isTrue);
    for(final action in ['import','unlink','follow','settings','sync']) {
      expect(GatewayRequest.canRetry('channel-source-sync',{'action':action}),isFalse);
    }
  });
  testWidgets('catalog refresh imports nothing; a selected channel follows, pauses and disconnects', (tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    const id='db:p1:channel:0000000000000000000000000001';
    var imports=0,linked=false,following=true;
    final actions=<String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home:ConnectedChannelsPage()));
      await tester.pumpAndSettle();
      expect(find.text('TNT Sports 1'),findsOneWidget);expect(imports,0);
      expect(find.text('Public playlist'),findsOneWidget);
      await tester.tap(find.byTooltip('Add to My Channels'));
      await tester.pumpAndSettle();expect(imports,1);
      expect(find.textContaining('Following'),findsOneWidget);
      await tester.tap(find.byTooltip('Connection settings'));await tester.pumpAndSettle();
      await tester.tap(find.text('Pause updates'));await tester.pumpAndSettle();
      expect(find.textContaining('Paused'),findsOneWidget);
      await tester.tap(find.text('Sync now'));await tester.pumpAndSettle();expect(imports,1);
      await tester.tap(find.byTooltip('Connection settings'));await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect and keep saved channel'));await tester.pumpAndSettle();
      expect(find.byTooltip('Add to My Channels'),findsOneWidget);expect(imports,1);
      expect(actions,containsAllInOrder(['catalog','import','catalog','follow','catalog','sync','catalog','unlink','catalog']));
      expect(tester.takeException(),isNull);await tester.pumpWidget(const SizedBox.shrink());
    },()=>MockClient((request) async {
      expect(request.url.path.endsWith('/channel-source-sync'),isTrue);
      final body=jsonDecode(request.body) as Map;final action=body['action'].toString();actions.add(action);
      if(action=='import'){expect(body['entry_id'],id);imports++;linked=true;}
      if(action=='follow')following=body['enabled']==true;
      if(action=='unlink')linked=false;
      final response=action=='catalog'?{
        'ok':true,'state':{'enabled':true,'status':'ok','entry_count':2,'last_checked_at':'2026-11-07T14:00:00Z'},'total':2,
        'entries':[
          {'id':id,'provider':1,'kind':'channel','name':'TNT Sports 1','category':'Sports','stream_count':1,
            'connection':linked?{'channel_id':'channel-1','follow_updates':following,'source_missing':false}:null},
          {'id':'db:p1:playlist:0000000000000000000000000002','provider':1,'kind':'playlist',
            'name':'Public playlist','category':'Playlists','stream_count':0},
        ],
      }:{'ok':true};
      return http.Response(jsonEncode(response),200,headers:{'content-type':'application/json'});
    }));
  });
}
