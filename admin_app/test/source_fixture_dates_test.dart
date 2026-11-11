import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/source_fixture_date_utils.dart';

void main() {
  final fixtures = <Map<String, dynamic>>[
    {
      'home_team': 'Arsenal', 'away_team': 'Chelsea',
      'match_time': '2026-11-11T19:00:00Z', 'status': 'NS',
    },
    {
      'home_team': 'Liverpool', 'away_team': 'Everton',
      'match_time': '2026-11-12T12:30:00Z', 'status': 'NS',
    },
  ];

  test('UTC kickoff is displayed in Myanmar date/time even at midnight', () {
    final value = sourceFixtureMmtKickoff('2026-11-11T19:00:00Z');
    expect(value?.year, 2026);
    expect(value?.month, 11);
    expect(value?.day, 12);
    expect(value?.hour, 1);
    expect(value?.minute, 30);
  });

  test('timezone offsets convert to MMT instead of device local', () {
    final value = sourceFixtureMmtKickoff('2026-11-11T07:00:00+09:00');
    expect(value?.year, 2026);
    expect(value?.month, 11);
    expect(value?.day, 11);
    expect(value?.hour, 4);
    expect(value?.minute, 30);
  });

  test('unknown timezone is not treated as a trusted kickoff', () {
    expect(sourceFixtureMmtKickoff('2026-11-11T19:00:00'), isNull);
    expect(sourceFixtureMmtKickoff('unknown time'), isNull);
  });

  test('empty chosen date describes actual available Myanmar dates', () {
    final reason = explainEmptyFixtureFilter(
      provider: 'CricHD', mode: 'date',
      selectedDate: DateTime(2026, 11, 11), rawMatches: fixtures,
    );
    expect(reason, contains('2 timed football fixtures'));
    expect(reason, contains('none on 11 Nov 2026 Myanmar Time'));
    expect(reason, contains('12 Nov 2026'));
    expect(reason, contains('Choose All'));
  });

  test('a matching Myanmar date does not produce a false warning', () {
    final reason = explainEmptyFixtureFilter(
      provider: 'CricHD', mode: 'date',
      selectedDate: DateTime(2026, 11, 12), rawMatches: fixtures,
    );
    expect(reason, isNull);
  });

  test('Live filter distinguishes scheduled from live match', () {
    final pending = explainEmptyFixtureFilter(
      provider: 'CricHD', mode: 'live',
      selectedDate: DateTime(2026, 11, 11), rawMatches: fixtures,
    );
    expect(pending, contains('none marked LIVE'));

    final liveFixtures = [
      {...fixtures.first, 'hot': true},
    ];
    final live = explainEmptyFixtureFilter(
      provider: 'CricHD', mode: 'live',
      selectedDate: DateTime(2026, 11, 11), rawMatches: liveFixtures,
    );
    expect(live, isNull);
  });

  test('all mode and invalid fixture timestamps never invent times', () {
    final all = explainEmptyFixtureFilter(
      provider: 'CricHD', mode: 'all',
      selectedDate: DateTime(2026, 11, 11), rawMatches: fixtures,
    );
    expect(all, isNull);
    final missing = explainEmptyFixtureFilter(
      provider: 'Rojadirecta', mode: 'date',
      selectedDate: DateTime(2026, 11, 11),
      rawMatches: [
        {'home_team': 'A', 'away_team': 'B', 'match_time': null},
        {'home_team': 'A', 'away_team': '', 'match_time': '2026-11-12T01:00:00Z'},
      ],
    );
    expect(missing, isNull);
  });
}
