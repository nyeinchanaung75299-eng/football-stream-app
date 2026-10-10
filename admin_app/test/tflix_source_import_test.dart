import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';
import 'package:football_admin/source_line_validation.dart';
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

  Map<String, dynamic> verifiedLine({DateTime? now}) => {
        'label': 'HD',
        'stream_type': 'dash',
        'url': 'https://video.fixture.test/live.mpd',
        'media_verified': true,
        'health_status': 'healthy',
        'checked_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'key_id': '00112233-4455-6677-8899-aabbccddeeff',
        'key_data': 'FFEEDDCCBBAA99887766554433221100',
      };

  Map<String, dynamic> sourceRow() => {
        'source_id': 'football-source',
        'league': 'Fixture football',
        'home_team': 'Fixture home',
        'away_team': 'Fixture away',
        'match_time': null,
        'anchors': [
          {
            'room_num': 'fixture-channel',
            'page_url': 'https://tflix.su/channel/fixture-channel',
            'nick_name': 'Fixture channel',
          }
        ],
      };

  Map<String, dynamic> targetRow() => {
        'id': 'match-1',
        'home_team': 'Home',
        'away_team': 'Away',
        'kickoff_at': DateTime.now().toUtc().toIso8601String(),
        'is_active': true,
        'is_featured': true,
        'publish_state': 'published',
      };

  test('a TFLIX manifest response alone is not a verified media stream', () {
    final now = DateTime.utc(2026, 10, 10, 12);
    final good = verifiedLine(now: now);
    expect(isVerifiedTflixLine(good, now: now), isTrue);
    for (final change in <Map<String, dynamic>>[
      {'media_verified': false},
      {'health_status': 'unknown'},
      {'checked_at': null},
      {
        'checked_at':
            now.subtract(const Duration(minutes: 11)).toIso8601String()
      },
      {'checked_at': now.add(const Duration(minutes: 5)).toIso8601String()},
      {'expires_at': now.add(const Duration(seconds: 15)).toIso8601String()},
      {'expires_at': 'invalid'},
      {'url': 'javascript:alert(1)'},
      {'url': 'https://tflix.su/football'},
      {'url': 'https://embed.fixture.test/player.php?channel=fixture'},
      {'stream_type': 'auto'},
      {'key_data': null},
      {'key_data': 'not-a-key'},
    ]) {
      expect(isVerifiedTflixLine({...good, ...change}, now: now), isFalse,
          reason: change.keys.join(','));
    }
    expect(
        isVerifiedTflixLine({
          ...good,
          'health_status': 'slow',
          'expires_at': now.add(const Duration(minutes: 2)).toIso8601String(),
        }, now: now),
        isTrue);
  });

  test(
      'ClearKey is retained as a complete DASH pair and normalized for Android',
      () {
    expect(sourceLineKeyFields(verifiedLine()), {
      'key_id': '00112233445566778899aabbccddeeff',
      'key_data': 'ffeeddccbbaa99887766554433221100',
    });
    expect(sourceLineKeyFields({...verifiedLine(), 'stream_type': 'hls'}),
        isEmpty);
    expect(sourceLineKeyFields({...verifiedLine(), 'key_data': null}), isEmpty);
    expect(sourceLineKeyFields({'stream_type': 'dash'}), isEmpty);
    expect(
        sourceLineKeyFields(
            {'stream_type': 'dash', 'key_id': null, 'key_data': null}),
        {'key_id': null, 'key_data': null});
  });

  testWidgets('TFLIX can be selected and explains an empty verified catalog',
      (tester) async {
    databaseHandler = (_) async => jsonResponse([]);
    final providers = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocoImportPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TFLIX'));
      await tester.pumpAndSettle();
      expect(providers, ['soco', 'tflix']);
      expect(find.text('Source: TFLIX'), findsOneWidget);
      expect(
          find.text(
              'No football matches with stream sources are listed by TFLIX right now. Try Channels.'),
          findsOneWidget);
      expect(find.text('Tomorrow'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              expect(request.url.path.endsWith('/source-match-list'), isTrue);
              providers
                  .add((jsonDecode(request.body) as Map)['source'].toString());
              return jsonResponse({'matches': []});
            }));
  });

  testWidgets(
      'TFLIX Channels lists candidates without inventing fixture or health',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    databaseHandler = (_) async => jsonResponse([]);
    final catalogs = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(
          const MaterialApp(home: SocoImportPage(initialSource: 'tflix')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Channels'));
      await tester.pumpAndSettle();
      expect(catalogs, ['matches', 'channels']);
      expect(find.text('Fixture sports channel'), findsOneWidget);
      expect(find.textContaining('Fixture sports channel vs'), findsNothing);
      expect(find.text('Broadcast channel'), findsOneWidget);
      expect(find.textContaining('CHECK STREAMS'), findsOneWidget);
      expect(find.textContaining('LIVE'), findsNothing);
      expect(find.textContaining('HEALTHY'), findsNothing);
      expect(find.text('Direct stream URL'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((request) async {
              expect(request.url.path.endsWith('/source-match-list'), isTrue);
              final body = jsonDecode(request.body) as Map;
              catalogs.add(body['catalog'].toString());
              return jsonResponse({
                'matches': body['catalog'] == 'channels'
                    ? [
                        {
                          ...sourceRow(),
                          'kind': 'channel',
                          'home_team': 'Fixture sports channel',
                          'away_team': '',
                          'is_live': true,
                        }
                      ]
                    : [],
              });
            }));
  });

  for (final savePath in ['insert', 'exact', 'logical']) {
    testWidgets(
        'TFLIX $savePath saves only verified lines and preserves ClearKey',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? savedBody;
      var extractionCount = 0;
      databaseHandler = (request) async {
        if (request.url.path.endsWith('/matches')) {
          return jsonResponse([targetRow()]);
        }
        if (request.method == 'POST' || request.method == 'PATCH') {
          savedBody =
              Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          return jsonResponse({'id': 'saved-line'});
        }
        final exact = request.url.queryParameters.containsKey('stream_url');
        return jsonResponse(
            (savePath == 'exact' && exact) || (savePath == 'logical' && !exact)
                ? {'id': 'existing-line'}
                : null);
      };

      await http.runWithClient(() async {
        await tester.pumpWidget(
            const MaterialApp(home: SocoImportPage(initialSource: 'tflix')));
        await tester.pumpAndSettle();
        expect(find.text('Fixture home vs Fixture away'), findsOneWidget);
        expect(extractionCount, 0,
            reason: 'Listing rooms must not auto-probe media');
        await tester.tap(find.textContaining('Fixture channel').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Select Stream Quality'), findsOneWidget);
        expect(find.text('ADD'), findsOneWidget);
        expect(find.text('Unverified'), findsNothing);
        expect(find.text('Expired'), findsNothing);
        await tester.tap(find.text('ADD'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('Home vs Away'));
        await tester.pumpAndSettle();
        expect(savedBody, isNotNull);
        expect(savedBody!['key_id'], '00112233445566778899aabbccddeeff');
        expect(savedBody!['key_data'], 'ffeeddccbbaa99887766554433221100');
        expect(extractionCount, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
          () => MockClient((request) async {
                if (request.url.path.endsWith('/stream-health')) {
                  return jsonResponse({'health_status': 'healthy'});
                }
                if (request.url.path.endsWith('/soco-links')) {
                  extractionCount++;
                  final body = jsonDecode(request.body) as Map;
                  expect(body['source'], 'tflix');
                  expect(body['skip_probe'], isFalse);
                  return jsonResponse({
                    'lines': [
                      verifiedLine(),
                      {
                        ...verifiedLine(),
                        'label': 'Unverified',
                        'media_verified': false
                      },
                      {
                        ...verifiedLine(),
                        'label': 'Expired',
                        'expires_at': DateTime.now()
                            .subtract(const Duration(minutes: 1))
                            .toIso8601String(),
                      },
                    ],
                  });
                }
                return jsonResponse({
                  'matches': [sourceRow()]
                });
              }));
    });
  }
}
