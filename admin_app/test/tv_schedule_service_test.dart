import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_admin/services/tv_schedule_service.dart';

void main() {
  test('TV guide finds only a nearby non-replay programme with both teams', () {
    const kickoff = '2026-10-29T19:45:00Z';
    final guide = TvScheduleGuide.fromJson({
      'timezone': 'Asia/Yangon',
      'channels': [
        {
          'id': 'tnt-1',
          'name': 'TNT Sports 1',
          'matchedEPG': true,
          'region': 'uk',
          'programmes': [
            {
              'start': DateTime.parse(kickoff).millisecondsSinceEpoch,
              'title': 'Everton vs Newcastle United',
            },
            {
              'start': DateTime.parse(kickoff)
                  .add(const Duration(hours: 3))
                  .millisecondsSinceEpoch,
              'title': 'Everton vs Newcastle United replay',
            },
          ],
        },
        {
          'id': 'other',
          'name': 'Other TV',
          'matchedEPG': true,
          'programmes': [
            {
              'start': DateTime.parse(kickoff).millisecondsSinceEpoch,
              'title': 'Everton vs Chelsea',
            },
          ],
        },
      ],
    });

    final airings = guide.airingsForMatch({
      'home_team': 'Everton',
      'away_team': 'Newcastle United',
      'kickoff_at': kickoff,
    });

    expect(airings, hasLength(1));
    expect(airings.single.channel, 'TNT Sports 1');
    expect(airings.single.region, 'uk');
  });

  test('TV guide loader uses the NCA relay and reads no playback fields', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/tv-schedule');
      expect(request.url.queryParameters['date'], '2026-10-29');
      expect(request.url.queryParameters['days'], '8');
      return http.Response(
        jsonEncode({
          'timezone': 'Asia/Yangon',
          'channels': [
            {
              'id': 'channel-1',
              'name': 'beIN SPORTS 1',
              'matchedEPG': true,
              'stream_url': 'https://not-used.example/private.m3u8',
              'programmes': [],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    final guide = await TvScheduleService(
      httpClient: client,
      apiBases: const ['https://guide.example'],
    ).load(now: DateTime.utc(2026, 10, 29));

    expect(guide.channels.single.name, 'beIN SPORTS 1');
    expect(guide.channels.single.programmes, isEmpty);
  });
}
