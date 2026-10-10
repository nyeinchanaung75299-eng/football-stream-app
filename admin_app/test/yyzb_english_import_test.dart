import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';
import 'package:football_admin/screens/live_links_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) databaseHandler;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://database.fixture.test',
      publishableKey: 'test-public-key',
      httpClient: MockClient((request) async {
        final response = await databaseHandler(request);
        return http.Response.bytes(response.bodyBytes, response.statusCode,
            headers: response.headers, request: request);
      }),
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

  testWidgets(
      'legacy YYZB display changes without renaming unrelated manual lines',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    databaseHandler = (request) async {
      if (request.url.path.endsWith('/matches')) {
        return jsonResponse([
          {
            'id': 'match-1',
            'home_team': '切尔西',
            'away_team': '斯图加特',
            'kickoff_at': DateTime.now().toUtc().toIso8601String(),
            'is_active': true,
            'is_featured': true,
            'publish_state': 'published',
          }
        ]);
      }
      expect(request.method, 'GET');
      return jsonResponse([
        {
          'id': 'legacy-line',
          'label': 'YYZB • 阿亮（粤语） • HD',
          'stream_type': 'hls',
          'stream_url': 'https://video.fixture.test/live.m3u8',
          'is_active': true,
        },
        {
          'id': 'manual-line',
          'label': '自定义线路',
          'stream_type': 'hls',
          'stream_url': 'https://manual.fixture.test/live.m3u8',
          'is_active': true,
        },
      ]);
    };
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chelsea vs VfB Stuttgart'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('YYZB • Streamer 1 (Cantonese) • HD'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('YYZB • Streamer 1 (Cantonese) • HD'), findsOneWidget);
    expect(find.text('自定义线路'), findsOneWidget);
    expect(find.textContaining('阿亮'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('older YYZB rows render English with room identities unchanged',
      (tester) async {
    databaseHandler = (_) async => jsonResponse([]);
    final checkedRooms = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: SocoImportPage(initialSource: 'yyzb')));
      await tester.pumpAndSettle();
      expect(
          find.text('1. FC Union Berlin vs SV 07 Elversberg'), findsOneWidget);
      expect(find.text('Bundesliga'), findsOneWidget);
      expect(find.textContaining('Streamer 1 (Cantonese)'), findsOneWidget);
      expect(find.textContaining('Streamer 2 (Mandarin)'), findsOneWidget);
      expect(find.textContaining('主播'), findsNothing);
      expect(checkedRooms.toSet(), {'room-cantonese', 'room-mandarin'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              final body = jsonDecode(request.body) as Map;
              if (request.url.path.endsWith('/soco-links')) {
                checkedRooms.add(body['room_num'].toString());
                return jsonResponse({'ready': true, 'line_count': 1});
              }
              return jsonResponse({
                'matches': [
                  {
                    'source_id': 'old-schedule',
                    'league': '德甲',
                    'home_team': '柏林联合',
                    'away_team': '埃弗斯堡',
                    'match_time': DateTime.now().toUtc().toIso8601String(),
                    'anchors': [
                      {'room_num': 'room-cantonese', 'nick_name': '主播一（粤语）'},
                      {'room_num': 'room-mandarin', 'nick_name': '主播二（普通话）'},
                    ],
                  }
                ],
              });
            }));
  });

  for (final mirror in [false, true]) {
    testWidgets(
        mirror
            ? 'YYZB mirror names recover legacy identity from authenticated room'
            : 'YYZB English display keeps legacy import identity across signed URLs',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const originalName = '阿亮（粤语）';
      const storedLabel = 'YYZB • $originalName • HD';
      final shownName = mirror ? 'YYZB Server 1' : 'Streamer 1 (Cantonese)';
      var inserts = 0;
      var updates = 0;
      var extraction = 0;
      final queryLabels = <String>[];
      databaseHandler = (request) async {
        if (request.url.path.endsWith('/matches')) {
          return jsonResponse([
            {
              'id': 'match-1',
              'home_team': 'Home',
              'away_team': 'Away',
              'kickoff_at': DateTime.now().toUtc().toIso8601String(),
              'is_active': true,
              'is_featured': true,
              'publish_state': 'published',
            }
          ]);
        }
        if (request.method == 'POST') {
          inserts++;
          return jsonResponse({'id': 'new-unwanted-row'});
        }
        if (request.method == 'PATCH') {
          updates++;
          expect(request.url.queryParameters['id'], 'eq.legacy-line');
          expect((jsonDecode(request.body) as Map)['stream_url'],
              'https://video.fixture.test/live.m3u8?signature=$extraction');
          return jsonResponse({'id': 'legacy-line'});
        }
        if (request.url.queryParameters.containsKey('stream_url')) {
          return jsonResponse(null); // Every extraction returns a rotated URL.
        }
        final label = request.url.queryParameters['label'];
        queryLabels.add(label ?? '');
        return jsonResponse(
            label == 'eq.$storedLabel' ? {'id': 'legacy-line'} : null);
      };

      await http.runWithClient(() async {
        await tester.pumpWidget(
            const MaterialApp(home: SocoImportPage(initialSource: 'yyzb')));
        await tester.pumpAndSettle();
        expect(find.text('SC Paderborn 07 vs VfB Stuttgart'), findsOneWidget);
        expect(find.text('Bundesliga'), findsOneWidget);
        expect(find.textContaining('阿亮'), findsNothing);
        expect(find.textContaining(shownName), findsOneWidget);
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.tap(find.textContaining(shownName).last);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.textContaining('SC Paderborn 07 vs VfB Stuttgart'),
              findsNWidgets(2));
          expect(find.textContaining('阿亮'), findsNothing);
          if (mirror) {
            expect(find.textContaining('YYZB Server 1 (Cantonese)'),
                findsOneWidget);
          }
          await tester.tap(find.text('ADD'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          await tester.tap(find.text('Home vs Away'));
          await tester.pumpAndSettle();
        }
        expect(updates, 2);
        expect(inserts, 0);
        expect(queryLabels, ['eq.$storedLabel', 'eq.$storedLabel']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
          () => MockClient((request) async {
                final body = jsonDecode(request.body) as Map;
                if (request.url.path.endsWith('/stream-health')) {
                  return jsonResponse({'health_status': 'healthy'});
                }
                if (request.url.path.endsWith('/soco-links')) {
                  expect(body['room_num'], 'unchanged-room-7');
                  if (body['status_only'] == true) {
                    return jsonResponse({'ready': true, 'line_count': 1});
                  }
                  extraction++;
                  return jsonResponse({
                    'anchor_name':
                        mirror ? originalName : 'Different fresh room nickname',
                    'lines': [
                      {
                        'label': 'HD',
                        'resolution': '1080p',
                        'stream_type': 'hls',
                        'url':
                            'https://video.fixture.test/live.m3u8?signature=$extraction',
                      }
                    ],
                  });
                }
                return jsonResponse({
                  'matches': [
                    {
                      'source_id': 'schedule-123',
                      'schedule_id': 'schedule-123',
                      'league': '德甲',
                      'home_team': '帕德博恩',
                      'away_team': '斯图加特',
                      'match_time': DateTime.now().toUtc().toIso8601String(),
                      'anchors': [
                        {
                          'uid': 'unchanged-user-7',
                          'room_num': 'unchanged-room-7',
                          'nick_name': mirror ? 'YYZB Server 1' : 'Streamer 1',
                          if (!mirror) 'nick_name_en': 'Streamer 1',
                          if (!mirror) 'original_nick_name': originalName,
                          if (!mirror) 'import_name': originalName,
                        }
                      ],
                    }
                  ],
                });
              }));
    });
  }
}
