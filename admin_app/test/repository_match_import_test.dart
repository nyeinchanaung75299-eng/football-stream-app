import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/repository_match_card.dart';
import 'package:football_admin/widgets/repository_match_import_sheet.dart';

void main() {
  const fixture = <String, dynamic>{
    'name': 'Moldova vs Kazakhstan',
    'stream_count': 3,
    'event_meta': {
      'home_team': 'Moldova',
      'away_team': 'Kazakhstan',
      'league': 'Nations League',
      'kickoff_at': '2026-11-13T19:00:00Z',
    },
  };
  testWidgets('Repository Matches only previews lines; publishing stays in Controls',
      (tester) async {
    var viewedLines = 0;
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RepositoryMatchCard(
      entry: fixture,
      onViewLines: () => viewedLines++,
    ))));
    expect(find.text('ADD MATCH TO LIVE'), findsNothing);
    expect(find.text('PICK IN BIG MATCHES'), findsNothing);
    await tester.tap(find.text('VIEW LINES'));
    await tester.pump();
    expect(viewedLines, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('repository fixture review returns the exact published UTC kickoff',
      (tester) async {
    DateTime? selected;
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: FilledButton(
        onPressed: () async {
          selected = await showModalBottomSheet<DateTime>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const RepositoryMatchImportSheet(entry: fixture),
          );
        },
        child: const Text('REVIEW'),
      )),
    )));
    await tester.tap(find.text('REVIEW'));
    await tester.pumpAndSettle();
    expect(find.text('14 Nov 2026 · 1:30 AM MMT'), findsOneWidget);
    await tester.tap(find.text('ADD MATCH + LINES'));
    await tester.pumpAndSettle();
    expect(selected, DateTime.parse('2026-11-13T19:00:00Z'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing kickoff cannot publish an invented current time',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: RepositoryMatchImportSheet(entry: {
        'stream_count': 2,
        'event_meta': {'home_team': 'Home', 'away_team': 'Away'}
      }),
    )));
    expect(find.text('SET KICKOFF (MMT)'), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'ADD MATCH + LINES'));
    expect(button.onPressed, isNull);
  });
}
