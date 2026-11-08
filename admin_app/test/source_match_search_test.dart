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

  test('missing kickoff timestamps remain after scheduled fixtures', () {
    final rows = <Map<String,dynamic>>[
      {'home_team':'Z','match_time':'2026-11-07T12:00:00Z'},
      {'home_team':'A','match_time':'2026-11-07T13:00:00Z'},
      {'home_team':'M'},
    ];
    rows.sort((a,b) => compareAdminSourceMatches(a,b,'soco'));
    expect(rows.map((row)=>row['home_team']), ['Z','A','M']);
  });

}
