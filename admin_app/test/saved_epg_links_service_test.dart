import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/services/saved_epg_links_service.dart';

void main() {
  test('counts only active channels with both stored EPG identifiers', () {
    final rows = <Map<String, dynamic>>[
      {'id': 'a', 'is_active': true, 'epg_id': 'a.example', 'epg_source': 'AU1'},
      {'id': 'b', 'is_active': true, 'epg_id': 'b.example', 'epg_source': 'US2'},
      {'id': 'c', 'is_active': true, 'epg_id': null, 'epg_source': 'MX1'},
      {'id': 'd', 'is_active': true, 'epg_id': 'd.example', 'epg_source': ' '},
      {'id': 'e', 'is_active': false, 'epg_id': 'e.example', 'epg_source': 'UK1'},
      {'id': 'a', 'is_active': true, 'epg_id': 'a.example', 'epg_source': 'AU1'},
    ];
    expect(savedEpgChannelIds(rows), {'a', 'b'});
  });

  test('returns saved mappings even when no live programmes exist', () {
    final rows = List<Map<String, dynamic>>.generate(169, (i) => {
      'id': 'channel-$i',
      'is_active': true,
      'epg_id': i < 100 ? 'guide-$i' : null,
      'epg_source': i < 100 ? 'US2' : null,
    });
    expect(savedEpgChannelIds(rows).length, 100);
    // Live programme data must be counted separately by TvScheduleGuide.
  });

  test('loads saved mappings from the authenticated channel catalog', () async {
    final client = SupabaseClient(
      'https://fixture.example',
      'public-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/channels');
        expect(request.url.queryParameters['select'],
            'id,is_active,epg_id,epg_source');
        return http.Response(jsonEncode([
          {
            'id': 'channel-au',
            'is_active': true,
            'epg_id': 'bein.sports.1.au',
            'epg_source': 'AU1',
          },
          {
            'id': 'channel-empty',
            'is_active': true,
            'epg_id': null,
            'epg_source': null,
          },
        ]), 200, headers: {'content-type': 'application/json'},
          request: request);
      }),
    );
    addTearDown(client.dispose);
    final linked = await SavedEpgLinksService(client).load();
    expect(linked, {'channel-au'});
  });
}
