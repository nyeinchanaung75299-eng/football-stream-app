import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/fixture_import_page.dart';
import 'package:football_admin/screens/live_links_page.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) handler;
  late MockClient rest;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    rest = MockClient((request) async {
      final response = await handler(request);
      return http.Response.bytes(response.bodyBytes, response.statusCode,
          headers: response.headers, request: request);
    });
    await Supabase.initialize(
      url: 'https://database.fixture.test',
      publishableKey: 'test-public-key',
      httpClient: rest,
      authOptions: const FlutterAuthClientOptions(
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': 'local-test-session',
      'refresh_token': 'local-test-refresh',
      'token_type': 'bearer',
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-01T00:00:00Z',
      },
    }));
  });

  tearDownAll(() async => Supabase.instance.dispose());

  http.Response jsonResponse(Object? data) =>
      http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'});

  Map<String, dynamic> match() => {
        'id': 'match-1',
        'home_team': 'Home',
        'away_team': 'Away',
        'kickoff_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
        'is_featured': true,
        'publish_state': 'published',
      };

  Map<String, dynamic> sourceMatch(String home) => {
        'source_id': home,
        'league': 'Fixture league',
        'home_team': home,
        'away_team': 'Away',
        'match_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'LIVE',
        'anchors': [
          {'room_num': 'fixture-room', 'name': 'Fixture anchor'}
        ],
      };

  testWidgets('a failed matches query shows Retry and recovers',
      (tester) async {
    var attempts = 0;
    handler = (_) async {
      attempts++;
      if (attempts == 1) return http.Response('{"message":"offline"}', 400);
      return jsonResponse([]);
    };
    await tester.pumpWidget(const MaterialApp(home: LiveLinksPage()));
    await tester.pumpAndSettle();
    expect(find.text('Could not load matches.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load matches.'), findsNothing);
    expect(find.text('ADD SERVER'), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server-query failure is retryable and Active blocks double taps',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var reads = 0;
    var writes = 0;
    final update = Completer<http.Response>();
    handler = (request) async {
      if (request.url.path.endsWith('/matches')) return jsonResponse([match()]);
      if (request.method == 'PATCH') {
        writes++;
        return update.future;
      }
      reads++;
      if (reads == 1) return http.Response('{"message":"offline"}', 400);
      return jsonResponse([
        {
          'id': 'line-1',
          'label': 'Fixture server',
          'stream_type': 'hls',
          'stream_url': 'https://video.fixture.test/live.m3u8',
          'is_active': true,
          'health_status': 'healthy',
        }
      ]);
    };
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Could not load servers.'));
    expect(find.text('Could not load servers.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Fixture server'));
    final toggle = find.byType(Switch).last;
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    await tester.tap(toggle);
    await tester.pump();
    expect(writes, 1);
    update.complete(http.Response('{"message":"update rejected"}', 400));
    await tester.pumpAndSettle();
    expect(find.text('Could not update the server. Please retry.'),
        findsOneWidget);
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old background source response cannot replace a new provider',
      (tester) async {
    final old = Completer<http.Response>();
    var fawa = 0;
    handler = (_) async => jsonResponse([]);
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: SocoImportPage(initialSource: 'fawa')));
      await tester.pumpAndSettle();
      expect(find.textContaining('First Fawa'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(fawa, 2);
      await tester.tap(find.text('ColaTV'));
      await tester.pumpAndSettle();
      expect(find.textContaining('New Cola'), findsOneWidget);
      old.complete(jsonResponse({
        'matches': [sourceMatch('Old Fawa')]
      }));
      await tester.pumpAndSettle();
      expect(find.textContaining('Old Fawa'), findsNothing);
      expect(find.textContaining('New Cola'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              final provider = (jsonDecode(request.body) as Map)['source'];
              if (provider == 'fawa') {
                fawa++;
                if (fawa == 2) return old.future;
                return jsonResponse({
                  'matches': [sourceMatch('First Fawa')]
                });
              }
              return jsonResponse({
                'matches': [sourceMatch('New Cola')]
              });
            }));
  });

  testWidgets('new fixture mode wins when older requests finish later',
      (tester) async {
    final older = Completer<http.Response>();
    var loads = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: FixtureImportPage()));
      await tester.tap(find.text('Live'));
      await tester.pump();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.textContaining('New All'), findsOneWidget);
      older.complete(jsonResponse({
        'matches': [sourceMatch('Old Live')]
      }));
      await tester.pumpAndSettle();
      expect(find.textContaining('Old Live'), findsNothing);
      expect(find.textContaining('New All'), findsOneWidget);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              loads++;
              if (loads == 1) return older.future;
              return jsonResponse({
                'matches': [sourceMatch('New All')]
              });
            }));
  });

  testWidgets('saving a source line does not wait for its health response',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final health = Completer<http.Response>();
    var writes = 0;
    var healthChecks = 0;
    handler = (request) async {
      if (request.url.path.endsWith('/matches')) return jsonResponse([match()]);
      if (request.method == 'POST') {
        writes++;
        return jsonResponse({'id': 'saved-line'});
      }
      return jsonResponse(null);
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: SocoImportPage(initialSource: 'fawa')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Streamer').last);
      // The source's extraction indicator remains behind the open modal.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Select Stream Quality'), findsOneWidget);
      await tester.tap(find.text('ADD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Choose NCA match'), findsOneWidget);
      await tester.tap(find.text('Home vs Away'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(healthChecks, 1);
      expect(health.isCompleted, isFalse);
      expect(find.text('Select Stream Quality'), findsNothing);
      expect(find.textContaining('added. Health check is pending.'),
          findsOneWidget);
      health.complete(jsonResponse({'health_status': 'healthy'}));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              if (request.url.path.endsWith('/stream-health')) {
                healthChecks++;
                expect(
                    (jsonDecode(request.body) as Map)['link_id'], 'saved-line');
                return health.future;
              }
              if (request.url.path.endsWith('/soco-links')) {
                return jsonResponse({
                  'live_status': true,
                  'lines': [
                    {
                      'label': 'HD',
                      'stream_type': 'hls',
                      'url': 'https://video.fixture.test/live.m3u8'
                    }
                  ]
                });
              }
              return jsonResponse({
                'matches': [sourceMatch('Fixture home')]
              });
            }));
  });
}
