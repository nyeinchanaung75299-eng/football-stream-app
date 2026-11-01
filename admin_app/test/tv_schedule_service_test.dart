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
          'image_url': 'https://example.test/tnt-1.png',
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
    expect(guide.channels.first.imageUrl, 'https://example.test/tnt-1.png');
  });

  test('channel guide keeps only live or next match times and hides replays', () {
    final now = DateTime.utc(2026, 10, 29, 12);
    final guide = TvScheduleGuide.fromJson({
      'channels': [
        {
          'id': 'sports',
          'name': 'Sports TV',
          'matchedEPG': true,
          'programmes': [
            {
              'start': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
              'end': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
              'title': 'Everton vs Newcastle United',
            },
            {
              'start': now.add(const Duration(hours: 3)).millisecondsSinceEpoch,
              'title': 'Chelsea vs Liverpool',
            },
            {
              'start': now.add(const Duration(hours: 4)).millisecondsSinceEpoch,
              'title': 'Chelsea vs Liverpool replay',
            },
            {
              'start': now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
              'title': 'Football news',
            },
          ],
        },
        {
          'id': 'not-matched',
          'name': 'Unmatched TV',
          'matchedEPG': false,
          'programmes': [
            {
              'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
              'title': 'Arsenal vs Spurs',
            },
          ],
        },
      ],
    });

    final listings = guide.liveAndUpcomingMatchListings(now: now);

    expect(listings, hasLength(2));
    expect(listings.first.isLive, isTrue);
    expect(listings.first.programme.title, 'Everton vs Newcastle United');
    expect(listings.last.programme.title, 'Chelsea vs Liverpool');
  });

  test('Non-football Australian rules teams are not football EPG matches', () {
    final now = DateTime.utc(2026, 11, 1, 2);
    final guide = TvScheduleGuide.fromJson({
      'channels': [
        {
          'id': 'tnt-4', 'name': 'TNT Sports 4',
          'matchedEPG': true,
          'programmes': [
            {
              'start': now.millisecondsSinceEpoch,
              'title': "Live: Women's Australian Rules",
              'subtitle': 'Essendon Bombers v Collingwood Magpies',
              'description': 'AFLW action from Melbourne',
            },
            {
              'start': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
              'title': 'Getafe vs Sevilla FC',
              'stream_ambiguous': true,
            },
            {
              'start': now.add(const Duration(hours: 2)).millisecondsSinceEpoch,
              'title': 'Getafe vs Sevilla FC',
              'description': 'Spanish La Liga live football',
            },
          ],
        },
      ],
    });
    final rows = guide.liveAndUpcomingMatchListings(now: now);
    expect(rows, hasLength(1));
    expect(rows.single.programme.title, 'Getafe vs Sevilla FC');
    expect(rows.single.programme.start,
        now.add(const Duration(hours: 2)));
  });

  test('Match airings recognise broadcaster club name variants', () {
    final kickoff = DateTime.utc(2026, 11, 1, 13);
    final guide = TvScheduleGuide.fromJson({
      'channels': [{
        'id': 'canal', 'name': 'Canal 5', 'matchedEPG': true,
        'programmes': [{
          'start': kickoff.subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
          'title': 'La Liga',
          'description': 'Getafe v Sevilla',
        }],
      }],
    });
    final airings = guide.airingsForMatch({
      'home_team': 'Getafe', 'away_team': 'Sevilla FC',
      'kickoff_at': kickoff.toIso8601String(),
    });
    expect(airings, hasLength(1));
    expect(airings.single.channel, 'Canal 5');
  });

  test('TV guide loader uses the NCA relay and reads no playback fields', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/tv-schedule');
      expect(request.url.queryParameters['date'], '2026-10-29');
      expect(request.url.queryParameters['days'], '3');
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
