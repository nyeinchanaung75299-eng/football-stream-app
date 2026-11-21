import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/services/source_resolution_cache.dart';
import 'package:football_admin/services/source_import_service.dart';
import 'package:football_admin/services/source_match_suggestions.dart';
import 'package:football_admin/services/myanmar_time.dart';

void main() {
  tearDown(SourceResolutionCache.clear);
  test(
      'resolution cache coalesces one room and rejects expired/session-old results',
      () async {
    SourceResolutionCache.bind('admin-a');
    var calls = 0;
    final gate = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> fetch() {
      calls++;
      return gate.future;
    }

    final a = SourceResolutionCache.load('soco', {'room_num': 'one'}, fetch);
    final b = SourceResolutionCache.load('soco', {'room_num': 'one'}, fetch);
    expect(identical(a, b), true);
    expect(calls, 1);
    SourceResolutionCache.clear();
    SourceResolutionCache.bind('admin-a');
    gate.complete({
      'lines': [
        {'url': 'https://cdn.example/old.m3u8'}
      ]
    });
    await a;
    await SourceResolutionCache.load('soco', {'room_num': 'one'}, () async {
      calls++;
      return {
        'lines': [
          {
            'url': 'https://cdn.example/expired.m3u8',
            'expires_at': '2020-01-01T00:00:00Z'
          }
        ]
      };
    });
    await SourceResolutionCache.load('soco', {'room_num': 'one'}, () async {
      calls++;
      return {'lines': []};
    });
    expect(calls, 3);
  });
  test(
      'uncertain atomic import retry reuses request UUID and preserves all configuration',
      () async {
    final bodies = <Map>[];
    var fail = true;
    final db = SupabaseClient('https://fixture.example', 'test-public',
        httpClient: MockClient((req) async {
      expect(req.url.path, endsWith('/rpc/import_match_source_lines'));
      final body = jsonDecode(req.body) as Map;
      bodies.add(body);
      if (fail) {
        fail = false;
        return http.Response('{"message":"temporary failure"}', 503,
            headers: {'content-type': 'application/json'}, request: req);
      }
      return http.Response(
          '{"ok":true,"match_id":"match","lines":[{"id":"saved"}]}', 200,
          headers: {'content-type': 'application/json'}, request: req);
    }));
    addTearDown(db.dispose);
    final service = SourceImportService(db);
    Future<Map<String, dynamic>> save() =>
        service.save(matchId: 'match', source: 'soco', room: {
          'room_num': 'room'
        }, lines: [
          {
            'url': 'https://cdn.example/live.mpd',
            'stream_type': 'dash',
            'referer': 'https://publisher.example/',
            'origin': 'https://publisher.example',
            'key_id': 'a' * 32,
            'key_data': 'b' * 32
          }
        ]);
    await expectLater(save(), throwsA(isA<PostgrestException>()));
    final result = await save();
    expect(result['ok'], true);
    expect(bodies.length, 2);
    expect(bodies[0], bodies[1]);
    expect((bodies[1]['p_lines'] as List).single['origin'],
        'https://publisher.example');
  });
  test(
      'destination suggestion respects home/away and verified time, preserving source fields',
      () {
    final source = {
      'home_team': 'FC Bayern Munich',
      'away_team': 'FC Köln',
      'match_time': '2026-11-21T20:00:00Z'
    };
    final correct = {
      'id': 'correct',
      'home_team': 'Bayern Munich',
      'away_team': 'FC Köln',
      'kickoff_at': '2026-11-21T20:00:00Z'
    };
    final wrongDay = {
      ...correct,
      'id': 'old',
      'kickoff_at': '2026-10-21T20:00:00Z'
    };
    final reversed = {
      ...correct,
      'id': 'reversed',
      'home_team': 'FC Köln',
      'away_team': 'Bayern Munich'
    };
    final before = jsonEncode(source);
    expect(
        suggestDestinations([wrongDay, reversed, correct], source).first['id'],
        'correct');
    expect(destinationScore(source, wrongDay), 0);
    expect(destinationScore(source, reversed), 0);
    expect(jsonEncode(source), before);
  });
  test('MMT date crosses UTC midnight and picker wall time round-trips', () {
    final utc = DateTime.parse('2026-11-21T20:00:00Z');
    final mmt = myanmarTime(utc);
    expect(mmt.day, 22);
    expect(mmt.hour, 2);
    expect(mmt.minute, 30);
    expect(myanmarWallToUtc(mmt), utc);
  });
}
