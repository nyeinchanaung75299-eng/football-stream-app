import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/football_match_guide_card.dart';

void main() {
  testWidgets('football match guide distinguishes verified EPG and upcoming times in MMT',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FootballMatchGuideCard(
          league: 'Spanish La Liga',
          match: 'Getafe vs Sevilla FC',
          kickoff: DateTime.utc(2026, 11, 1, 13),
          live: false,
          airings: [
            FootballGuideAiring(
              channel: 'Canal 5',
              when: DateTime.utc(2026, 11, 1, 12, 55),
              region: 'MX',
            ),
            FootballGuideAiring(
              channel: 'Premier Sports 2 UK',
              when: DateTime.utc(2026, 11, 1, 12, 55),
              region: 'UK',
            ),
          ],
          possibleAirings: [
            FootballGuideAiring(
              channel: 'TSN 3',
              when: DateTime.utc(2026, 11, 1, 13),
              title: 'Spanish Primera Division Soccer',
            ),
          ],
        ),
      ),
    ));
    expect(find.text('Spanish La Liga'), findsOneWidget);
    expect(find.text('Getafe vs Sevilla FC'), findsOneWidget);
    expect(find.text('UPCOMING'), findsOneWidget);
    expect(find.textContaining('EPG VERIFIED'), findsOneWidget);
    expect(find.textContaining('LIVE ONLY'), findsNothing);
    expect(find.textContaining('Canal 5'), findsOneWidget);
    expect(find.textContaining('Premier Sports 2 UK'), findsOneWidget);
    expect(find.textContaining('07:30 PM MMT'), findsOneWidget);
    expect(find.textContaining('POSSIBLE FOOTBALL AIRINGS'), findsOneWidget);
    expect(find.textContaining('TSN 3'), findsOneWidget);
  });
}
