import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/match_destination_sheet.dart';

void main() {
  testWidgets('source match destination can search teams and returns only the chosen match', (tester) async {
    String? chosen;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      child: const Text('Open'), onPressed: () async {
        chosen = await showModalBottomSheet<String>(context: context, isScrollControlled: true,
          builder: (_) => MatchDestinationSheet(matches: [
            {'id':'napoli','home_team':'Napoli','away_team':'Inter','league':'Serie A'},
            {'id':'spurs','home_team':'Tottenham Hotspur','away_team':'Leeds','league':'Premier League'},
          ]));
      },
    )))));
    await tester.tap(find.text('Open'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Napoli');await tester.pumpAndSettle();
    expect(find.text('Napoli vs Inter'), findsOneWidget);
    expect(find.text('Tottenham Hotspur vs Leeds'), findsNothing);
    await tester.tap(find.text('Napoli vs Inter'));await tester.pumpAndSettle();
    expect(chosen, 'napoli');
  });
}
