import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/repository_match_card.dart';

void main() {
  testWidgets(
    'repository card keeps line action and shows MMT kickoff between teams',
    (tester) async {
      var opened = 0;
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RepositoryMatchCard(
              entry: const {
                'name': 'Moldova vs Kazakhstan',
                'stream_count': 6,
                'event_meta': {
                  'home_team': 'Moldova',
                  'away_team': 'Kazakhstan',
                  'league': 'UEFA Nations League',
                  'kickoff_at': '2026-11-13T19:00:00Z',
                },
              },
              onViewLines: () => opened++,
            ),
          ),
        ),
      );
      expect(find.text('Moldova'), findsOneWidget);
      expect(find.text('Kazakhstan'), findsOneWidget);
      expect(find.text('1:30 AM'), findsOneWidget);
      expect(find.text('14 Nov · MMT'), findsOneWidget);
      expect(find.text('6 UNIQUE LINES'), findsOneWidget);
      expect(find.text('PICK IN BIG MATCHES'), findsNothing);
      expect(find.byIcon(Icons.playlist_add_rounded), findsNothing);
      await tester.tap(find.text('VIEW LINES'));
      expect(opened, 1);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing source time is never replaced with the current clock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepositoryMatchCard(
            entry: const {'name': 'Home vs Away', 'stream_count': 0},
            onViewLines: () {},
          ),
        ),
      ),
    );
    expect(find.text('Time pending'), findsOneWidget);
    expect(find.text('Not provided'), findsOneWidget);
    expect(find.text('0 UNIQUE LINES'), findsOneWidget);
  });
}
