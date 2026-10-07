import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:football_viewer/screens/home_page.dart';

void main() {
  const fallbackEnabled =
      String.fromEnvironment('ENABLE_NO_VPN_FALLBACK', defaultValue: '0') == '1';
  final kickoff = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> match(int count) => {
        'id': 'match-1',
        'league': 'Test league',
        'home_team': 'Home',
        'away_team': 'Away',
        'kickoff_at': kickoff,
        'is_live': true,
        'stream_count': count,
        'stream_links': <Map<String, dynamic>>[],
      };
  const oldLine = <String, dynamic>{
    'id': 'old-line',
    'label': 'Old mirror line',
    'stream_type': 'hls',
    'stream_url': 'https://example.test/old.m3u8',
    'is_active': true,
    'priority': 1,
  };

  setUp(() {
    // iOS has no APK update checks, keeping these feed tests self-contained.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NCA',
      packageName: 'football_viewer',
      version: '9.8.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  MockClient api({
    required int Function() count,
    required Future<http.Response> Function() streams,
  }) =>
      MockClient((request) async {
        if (request.url.path.endsWith('/streams')) return streams();
        if (request.url.path.endsWith('/matches')) {
          return http.Response(jsonEncode({'matches': [match(count())]}), 200);
        }
        if (request.url.path.endsWith('matches.json')) {
          return http.Response(
            jsonEncode([
              {...match(1), 'stream_links': [oldLine]},
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });

  testWidgets('authoritative zero stays NOT READY despite a stale mirror',
      (tester) async {
    var streamRequests = 0;
    final client = api(
      count: () => 0,
      streams: () async {
        streamRequests++;
        return http.Response('{"streams":[]}', 200);
      },
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(httpClient: client)));
    await tester.pumpAndSettle();
    expect(find.text('NOT READY'), findsOneWidget);
    expect(find.textContaining('WATCH LIVE'), findsNothing);
    expect(streamRequests, 0);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('successful empty streams revoke cached and mirrored lines',
      (tester) async {
    var configured = true;
    final client = api(
      count: () => configured ? 1 : 0,
      streams: () async => http.Response(
        jsonEncode({'streams': configured ? [oldLine] : []}),
        200,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(httpClient: client)));
    await tester.pumpAndSettle();
    expect(find.text('WATCH LIVE'), findsOneWidget);
    configured = false;
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();
    expect(find.text('NOT READY'), findsOneWidget);
    expect(find.textContaining('WATCH LIVE'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('a slow successful empty response beats the old mirror',
      (tester) async {
    final client = api(
      count: () => 1,
      streams: () async {
        await Future<void>.delayed(const Duration(milliseconds: 3200));
        return http.Response('{"streams":[]}', 200);
      },
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(httpClient: client)));
    // Render the match while its stream prefetch is still waiting.
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('WATCH LIVE'));
    await tester.pump(const Duration(milliseconds: 3050));
    expect(find.text('Choose line'), findsNothing);
    expect(find.text('Old mirror line'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('NOT READY'), findsOneWidget);
    expect(find.text('Choose line'), findsNothing);
    if (fallbackEnabled) {
      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(
        prefs.getString('viewer_authoritative_matches_v1')!,
      ) as List;
      expect((cached.single as Map)['stream_count'], 0);
      expect((cached.single as Map)['stream_links'], isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('an actual stream API failure still offers a mirror backup',
      (tester) async {
    final client = api(
      count: () => 1,
      streams: () async => http.Response('{}', 503),
    );
    await tester.pumpWidget(MaterialApp(home: HomePage(httpClient: client)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WATCH LIVE'));
    await tester.pumpAndSettle();
    expect(find.text('Choose line'), findsOneWidget);
    expect(find.text('Old mirror line'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  }, skip: !fallbackEnabled);
}
