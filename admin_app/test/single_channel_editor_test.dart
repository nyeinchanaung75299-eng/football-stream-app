import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/channels_page.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://fixture.example',
        publishableKey: 'test-public',
        httpClient: MockClient((request) async {
          final rows = request.url.path.endsWith('/channels')
              ? [
                  {
                    'id': 'channel',
                    'name': 'TV',
                    'category': 'Sport',
                    'is_active': true
                  }
                ]
              : [
                  {
                    'id': 'line',
                    'label': 'Server 1',
                    'stream_url': 'https://media.example/live.m3u8'
                  }
                ];
          return http.Response(jsonEncode(rows), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }),
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets(
      'editing a channel exposes one stream without server or add-line controls',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Channel'), findsOneWidget);
    expect(find.text('Server name'), findsNothing);
    expect(find.text('ADD LINE'), findsNothing);
    expect(find.text('Line 1'), findsNothing);
    expect(find.widgetWithText(TextField, 'Stream URL (M3U8 / MPD / MP4)'),
        findsOneWidget);
  });
}
