import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/live_links_page.dart';

void main() {
  late MockClient client;
  Map<String, dynamic>? saved;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    client = MockClient((request) async {
      Object data = [];
      if (request.url.path.endsWith('/matches')) {
        data = [
          {
            'id': 'match-1',
            'home_team': 'Home',
            'away_team': 'Away',
            'league': 'League',
            'kickoff_at': '2026-10-29T12:00:00Z',
            'is_active': true,
            'is_featured': true,
            'publish_state': 'published'
          }
        ];
      } else if (request.method == 'POST') {
        saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'}, request: request);
    });
    await Supabase.initialize(
        url: 'https://fixture.example',
        publishableKey: 'test-public',
        httpClient: client,
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false));
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets('tap a match opens simple form and saves stream metadata',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: LiveLinksPage()));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('|'));
    expect(find.text('Resolution'), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Live Links Upload'), findsOneWidget);
    expect(find.text('Advanced options'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    Future<void> fill(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }

    await fill('Resolution', '1080p');
    await fill('Link', 'https://media.example/live.mpd');
    await fill('Referer', 'https://player.example');
    await fill('Origin', 'https://player.example');
    await fill('keyID', '00112233445566778899aabbccddeeff');
    await fill('keyData', 'ffeeddccbbaa99887766554433221100');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SAVE LINK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE LINK'));
    await tester.pumpAndSettle();
    expect(saved?['match_id'], 'match-1');
    expect(saved?['stream_type'], 'dash');
    expect(saved?['resolution'], '1080p');
    expect(saved?['referer'], 'https://player.example');
    expect(saved?['key_id'], '00112233445566778899aabbccddeeff');
    expect(find.text('Server added.'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('|'));
  });
}
