import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/source_match_discovery.dart';

void main() {
  group('source stream availability', () {
    for (final source in ['soco', 'yyzb']) {
      test('$source schedule IDs never become streamer rooms', () {
        expect(
          sourceMatchAnchors({
            'source_id': 'fixture-123',
            'schedule_id': 'fixture-123',
            'page_url': 'https://example.test/schedule/123',
            'anchors': <Object>[],
          }, source),
          isEmpty,
        );
        expect(
          sourceMatchAnchors({
            'source_id': 'fixture-123',
            'anchors': [
              {'room_num': '', 'page_url': ''},
            ],
          }, source),
          isEmpty,
        );
      });
    }

    test('real anchor rooms retain their source metadata', () {
      final anchor = {
        'room_num': 'streamer-456',
        'nickname': 'Original streamer',
        'page_url': 'https://example.test/room/456',
      };
      expect(
        sourceMatchAnchors({
          'source_id': 'fixture-123',
          'anchors': [
            anchor,
            {'room_num': ''},
            'invalid',
          ],
        }, 'yyzb'),
        [anchor],
      );
    });

    for (final source in ['fawa', 'cola']) {
      test('$source retains its existing page and room fallback', () {
        expect(
          sourceMatchAnchors({
            'source_id': 'room-123',
            'page_url': 'https://example.test/live/123',
          }, source),
          [
            {
              'room_num': 'room-123',
              'page_url': 'https://example.test/live/123',
            },
          ],
        );
        expect(
          sourceMatchAnchors({'page_url': 'https://example.test/live'}, source),
          [
            {'room_num': '', 'page_url': 'https://example.test/live'},
          ],
        );
      });
    }
  });

  test('kickoff order wins over live and featured flags', () {
    final matches = <SourceMatch>[
      {'source_id': 'ordinary', 'match_time': '2026-10-10T10:00:00Z'},
      {
        'source_id': 'featured',
        'hot': true,
        'match_time': '2026-10-10T15:00:00Z',
      },
      {'source_id': 'live', 'live': true, 'match_time': '2026-10-10T12:00:00Z'},
    ];
    final originalTimes = {
      for (final match in matches) match['source_id']: match['match_time'],
    };
    matches.sort(
      (a, b) =>
          compareSourceMatches(a, b, isLive: (match) => match['live'] == true),
    );
    expect(matches.map((match) => match['source_id']), [
      'ordinary',
      'live',
      'featured',
    ]);
    expect({
      for (final match in matches) match['source_id']: match['match_time'],
    }, originalTimes);
  });

  test('00:30 is always before 02:30, even when 02:30 is featured', () {
    final schedule = <SourceMatch>[
      {'source_id':'0230-hot', 'hot':true, 'match_time':'2026-11-02T20:00:00Z'},
      {'source_id':'0030', 'match_time':'2026-11-02T18:00:00Z'},
      {'source_id':'0200', 'match_time':'2026-11-02T19:30:00Z'},
      {'source_id':'0230-other', 'match_time':'2026-11-02T20:00:00Z'},
    ];
    schedule.sort((a,b) => compareSourceMatches(a,b,isLive:(_)=>false));
    expect(schedule.map((x)=>x['source_id']),
      ['0030','0200','0230-hot','0230-other']);
  });

  test('simultaneous kickoffs have stable ordering across feed refreshes', () {
    final a = <String, dynamic>{
      'source_id': 'a',
      'match_time': '2026-10-10T14:00:00Z',
    };
    final b = <String, dynamic>{
      'source_id': 'b',
      'match_time': '2026-10-10T14:00:00Z',
    };
    for (final incoming in [
      [b, a],
      [a, b],
    ]) {
      incoming.sort((a, b) => compareSourceMatches(a, b, isLive: (_) => false));
      expect(incoming.map((match) => match['source_id']), ['a', 'b']);
    }
  });

  test('YYZB major football competitions lead, then keep kickoff order', () {
    final matches = <SourceMatch>[
      {'source_id': 'minor', 'league': 'Portugal U23 League', 'match_time': '2026-11-03T10:00:00Z'},
      {'source_id': 'ucl', 'league': 'UEFA Champions League', 'match_time': '2026-11-03T20:00:00Z'},
      {'source_id': 'epl', 'league': 'English Premier League', 'match_time': '2026-11-03T18:00:00Z'},
      {'source_id': 'uel', 'league': 'UEFA Europa League', 'match_time': '2026-11-03T19:00:00Z'},
    ];
    matches.sort((a, b) => compareSourceMatches(
      a,
      b,
      isLive: (_) => false,
      majorCompetitionFirst: true,
    ));
    expect(matches.map((match) => match['source_id']), [
      'ucl',
      'uel',
      'epl',
      'minor',
    ]);
  });

  group('source discovery filters', () {
    final today = DateTime(2026, 10, 10, 12);
    final matches = <SourceMatch>[
      {
        'source_id': 'today',
        'league': 'English Premier League',
        'home_team': 'Arsenal',
        'away_team': 'Leeds',
        'match_time': DateTime(2026, 10, 10).toUtc().toIso8601String(),
      },
      {
        'source_id': 'yesterday',
        'league': 'Bundesliga',
        'home_team': 'Bayern',
        'away_team': 'Union Berlin',
        'match_time': DateTime(2026, 10, 9, 23, 59).toUtc().toIso8601String(),
      },
      {
        'source_id': 'tomorrow',
        'league': 'English Premier League',
        'home_team': 'Chelsea',
        'away_team': 'Bournemouth',
        'match_time': DateTime(2026, 10, 11).toUtc().toIso8601String(),
      },
      {
        'source_id': 'unknown',
        'league': 'Bundesliga',
        'home_team': 'Dortmund',
        'away_team': 'Mainz',
      },
    ];

    test('Today uses the local calendar, excluding unknown kickoff times', () {
      final filtered = filterSourceMatches(
        matches,
        todayOnly: true,
        now: today,
      );
      expect(filtered.map((match) => match['source_id']), ['today']);
    });

    test('All dates retains past, future, and unknown-time fixtures', () {
      expect(
        filterSourceMatches(matches, todayOnly: false, now: today),
        matches,
      );
    });

    test('search combines team and league words without changing fixtures', () {
      final filtered = filterSourceMatches(
        matches,
        todayOnly: false,
        query: '  PREMIER   arsenal  ',
      );
      expect(filtered.map((match) => match['source_id']), ['today']);
      expect(identical(filtered.single, matches.first), isTrue);
      expect(
        filterSourceMatches(matches, todayOnly: false, query: 'Chelsea Leeds'),
        isEmpty,
      );
    });

    test('league filter is exact and composes with date and search', () {
      expect(
        filterSourceMatches(
          matches,
          todayOnly: true,
          now: today,
          league: 'English Premier League',
          query: 'leeds',
        ),
        [matches.first],
      );
      expect(
        filterSourceMatches(
          matches,
          todayOnly: false,
          league: 'Premier League',
        ),
        isEmpty,
      );
    });

    test(
      'league picker deduplicates names and makes Premier League easy to find',
      () {
        expect(sourceMatchLeagues(matches), [
          'English Premier League',
          'Bundesliga',
        ]);
      },
    );
  });
}
