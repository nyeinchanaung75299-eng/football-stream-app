import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/source_match_search.dart';

void main() {
  test('Spurs aliases and league/team terms find the original fixture', () {
    final match = <String, dynamic>{'home_team': 'Leeds United',
      'away_team': 'Tottenham Hotspur', 'league': 'Premier League'};
    for (final query in ['Leeds', 'Tottenham', 'Spurs', 'စပါး', 'Premier Spurs', 'Leeds vs Spurs']) {
      expect(sourceMatchMatchesQuery(match, query), isTrue);
    }
    expect(sourceMatchMatchesQuery(match, 'Bristol'), isFalse);
    expect(match['away_team'], 'Tottenham Hotspur');
  });

  test('partial kickoff metadata never buries an imminent Totalsportek fixture', () {
    final leeds = <String, dynamic>{'home_team': 'Leeds United',
      'countdown_minutes': 75, 'match_time': null, 'anchors': []};
    final bristol = <String, dynamic>{'home_team': 'Bristol City',
      'countdown_minutes': 75, 'match_time': '2026-11-07T12:30:00Z'};
    final clermont = <String, dynamic>{'home_team': 'Clermont',
      'countdown_minutes': 105, 'match_time': '2026-11-07T13:00:00Z'};
    final rows = [clermont, leeds, bristol];
    rows.sort((a,b) => compareAdminSourceMatches(a,b,'totalsportek'));
    expect(rows.map((row) => row['home_team']), ['Bristol City','Leeds United','Clermont']);
    leeds['match_time'] = '2026-11-07T12:30:00Z';
    rows.sort((a,b) => compareAdminSourceMatches(a,b,'totalsportek'));
    expect(rows.map((row) => row['home_team']), ['Bristol City','Leeds United','Clermont']);
  });

  test('missing countdowns keep a stable order while timestamps arrive', () {
    final rows = <Map<String,dynamic>>[
      {'home_team':'Z','match_time':'2026-11-07T12:00:00Z'},
      {'home_team':'A','match_time':'2026-11-07T13:00:00Z'},
      {'home_team':'M'},
    ];
    rows.sort((a,b) => compareAdminSourceMatches(a,b,'totalsportek'));
    expect(rows.map((row)=>row['home_team']), ['A','M','Z']);
    rows.sort((a,b) => compareAdminSourceMatches(a,b,'soco'));
    expect(rows.map((row)=>row['home_team']), ['Z','A','M']);
  });
}
