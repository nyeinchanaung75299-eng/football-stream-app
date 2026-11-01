import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/services/channel_source_service.dart';

void main() {
  test('channel search handles case, spaces, category and number shortcuts',
      () {
    const row = {'name': 'BEIN SPORTS 1', 'category': 'Sport'};
    expect(channelMatchesSearch(row, '  bein1 '), isTrue);
    expect(channelMatchesSearch(row, 'SPORT'), isTrue);
    expect(channelMatchesSearch(row, 'bein 2'), isFalse);
    expect(channelMatchesSearch(row, ''), isTrue);
  });

  test('team search finds EPG-confirmed Fubo channels ahead of name matches', () {
    const channels = <Map<String, dynamic>>[
      {'id': 'willow', 'name': 'WILLOW SPORTS HD', 'category': 'Cricket'},
      {'id': 'fubo1', 'name': 'FUBO SPORTS FHD', 'category': 'Sports'},
      {'id': 'fubo2', 'name': 'Fubo Sports Network Canada', 'category': 'Sports'},
      {'id': 'arsenal', 'name': 'Arsenal TV', 'category': 'Club'},
    ];
    const guide = <Map<String, dynamic>>[
      {'channel_id': 'fubo1', 'home_team': 'Liverpool', 'away_team': 'Arsenal'},
      {'channel_id': 'fubo2', 'home_team': 'Liverpool', 'away_team': 'Arsenal'},
      {'channel_id': 'willow', 'home_team': 'Bengal', 'away_team': 'Mumbai'},
    ];
    final matches = searchChannelsWithEpg(channels, guide, 'Arsenal');
    expect(matches.map((row) => row['id']).toList(),
        ['fubo1', 'fubo2', 'arsenal']);
    expect(matches.first['epg_fixture'], 'Liverpool Arsenal');
    expect(searchChannelsWithEpg(channels, guide, 'Fubo').length, 2);
    expect(searchChannelsWithEpg(channels, guide, '').length, 4);
    expect(searchChannelsWithEpg(channels, [], 'Willow').length, 1);
  });

  test(
      'selection reads the first active private line and preserves DRM/headers',
      () async {
    final client = SupabaseClient('https://fixture.example', 'public-key',
        httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/channel_lines');
      expect(request.url.queryParameters['channel_id'], 'eq.channel-1');
      expect(request.url.queryParameters['is_active'], 'eq.true');
      expect(request.url.queryParameters['limit'], '1');
      return http.Response(
          jsonEncode([
            {
              'stream_url': 'https://origin.example/live.mpd?token=fixture',
              'stream_type': 'dash',
              'referer': 'https://player.example/watch',
              'origin': 'https://player.example',
              'key_id': '00112233445566778899aabbccddeeff',
              'key_data': 'ffeeddccbbaa99887766554433221100',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request);
    }));
    addTearDown(client.dispose);
    final result = await ChannelSourceService(client)
        .select({'id': 'channel-1', 'name': 'Sports'});
    expect(result.streamUrl, 'https://origin.example/live.mpd?token=fixture');
    expect(result.streamType, 'dash');
    expect(result.channelName, 'Sports');
    expect(result.referer, 'https://player.example/watch');
    expect(result.origin, 'https://player.example');
    expect(result.keyId, '00112233445566778899aabbccddeeff');
    expect(result.keyData, 'ffeeddccbbaa99887766554433221100');
  });

  test('missing active lines cannot become a blank match stream', () async {
    final client = SupabaseClient('https://fixture.example', 'public-key',
        httpClient: MockClient((request) async => http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: request)));
    addTearDown(client.dispose);
    await expectLater(
        ChannelSourceService(client).select({'id': 'empty', 'name': 'Empty'}),
        throwsStateError);
  });

  test('malformed URLs and incomplete key pairs are rejected before prefilling',
      () {
    for (final line in [
      {'stream_url': 'file:///private/file'},
      {'stream_url': 'https://user:pass@origin.example/a.mpd'},
      {'stream_url': 'https://origin.example/a.mpd', 'key_id': 'kid'},
    ]) {
      expect(() => ChannelStreamSelection.fromRows({'name': 'Channel'}, line),
          throwsFormatException);
    }
  });
}
