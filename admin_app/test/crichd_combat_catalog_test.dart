import 'dart:convert';
import 'package:flutter/material.dart';
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
    await Supabase.initialize(
        url: 'https://database.fixture.test',
        publishableKey: 'fixture-public',
        httpClient: MockClient((r) async => http.Response('[]', 200)),
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false));
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'fixture-session',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-4000-8000-000000000001',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z'
      }
    }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets(
      'CricHD Football and Combat use isolated metadata requests and category filters',
      (tester) async {
    final requests = <Map>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: SocoImportPage(initialSource: 'crichd')));
      await tester.pumpAndSettle();
      expect(requests.last['sport'], isNull);
      await tester.tap(find.text('Combat Sports'));
      await tester.pumpAndSettle();
      expect(requests.last['sport'], 'combat');
      expect(requests.last['category'], 'all');
      expect(
          find.textContaining('No published events for this combat category'),
          findsOneWidget);
      await tester.tap(find.text('All combat sports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UFC').last);
      await tester.pumpAndSettle();
      expect(requests.last['category'], 'ufc');
      await tester.tap(find.text('Football'));
      await tester.pumpAndSettle();
      expect(requests.last['sport'], isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              final body = jsonDecode(request.body) as Map;
              requests.add(body);
              return http.Response(
                  jsonEncode({
                    'ok': true,
                    'source': 'crichd',
                    'sport': body['sport'] ?? 'football',
                    'matches': [],
                    'diagnostics': {
                      'content_state': 'no_published_combat_events'
                    }
                  }),
                  200,
                  headers: {'content-type': 'application/json'});
            }));
  });
}
