import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/source_browser_page.dart';
import 'package:football_viewer/viewer_tab_cache.dart';

void main() {
  setUp(() {
    ViewerTabCache.clearForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'YYZB saves successful public listings safely and restores after reload',
    (tester) async {
      final now = DateTime.now();
      // Same upcoming fixture shape as the verified legacy YYZB room tests.
      final start = DateTime(now.year, now.month, now.day, 23, 59)
          .toUtc().toIso8601String();
      final current = <String, dynamic>{
        'source_id': 'fixture-42',
        'home_team': '帕德博恩',
        'away_team': '斯图加特',
        'league': '德甲',
        'match_time': start,
        'stream_url': 'https://secret.example/stream?token=private',
        'key_data': 'secret-drm',
        'anchors': [
          {'room_num': 'room-1', 'nick_name': '足球主播',
           'headers': {'Authorization': 'private-secret'}},
        ],
      };

      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: SourceBrowserPage(source: 'yyzb'),
        ));
        await tester.pumpAndSettle();
        expect(find.text('SC Paderborn 07'), findsOneWidget);
        expect(find.text('VfB Stuttgart'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('viewer_source_cache_v1_yyzb');
        expect(saved, isNotNull);
        expect(saved, contains('room-1'));
        expect(saved, isNot(contains('secret-drm')));
        expect(saved, isNot(contains('private-secret')));
        expect(saved, isNot(contains('stream_url')));
        final rows = jsonDecode(saved!)['matches'] as List;
        expect(rows.length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => MockClient((request) async {
        if (request.url.path.endsWith('/matches')) {
          return http.Response(jsonEncode({'matches': [current]}), 200);
        }
        return http.Response('{}', 404);
      }));

      // Simulate Safari discarding the Flutter app's RAM, not browser storage.
      ViewerTabCache.clearForTesting();
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: SourceBrowserPage(source: 'yyzb'),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.text('SC Paderborn 07'), findsOneWidget);
        expect(find.text('Loading YYZB…'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((_) async => http.Response('{}', 503)));
    },
  );

  test('saved source snapshots remain valid even after authoritative empty', () async {
    final now = DateTime.now().toUtc();
    ViewerTabCache.seedStaleSourceIfMissing('soco', [
      {'source_id': 'previous'},
    ]);
    expect(ViewerTabCache.sourceRows('soco')!.length, 1);
    expect(ViewerTabCache.sourceFresh('soco', now: now), isFalse);
    await ViewerTabCache.loadSource('soco', () async => [], force: true);
    expect(ViewerTabCache.sourceRows('soco'), isEmpty);
    ViewerTabCache.seedStaleSourceIfMissing('soco', [
      {'source_id': 'deleted'},
    ]);
    expect(ViewerTabCache.sourceRows('soco'), isEmpty);
  });

  test('restored public Channels data cannot replace newer success', () async {
    ViewerTabCache.seedStaleChannelsIfMissing([
      {'id': 'old', 'name': 'Old Channel'},
    ]);
    expect(ViewerTabCache.channelsFresh(), isFalse);
    await ViewerTabCache.loadChannels(() async => [], force: true);
    expect(ViewerTabCache.channelRows, isEmpty);
    ViewerTabCache.seedStaleChannelsIfMissing([
      {'id': 'deleted', 'name': 'Deleted Channel'},
    ]);
    expect(ViewerTabCache.channelRows, isEmpty);
  });
}
