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

  test('real live fixtures sort before featured upcoming fixtures', () {
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
      'live',
      'featured',
      'ordinary',
    ]);
    expect({
      for (final match in matches) match['source_id']: match['match_time'],
    }, originalTimes);
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
