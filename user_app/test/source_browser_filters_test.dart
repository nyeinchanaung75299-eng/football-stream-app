import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/source_browser_page.dart';
import 'package:football_viewer/widgets/source_match_filters.dart';

List<Map<String, dynamic>> _fixtures() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 23, 59);
  return [
    {
      'source_id': 'today-featured',
      'league': 'English Premier League',
      'home_team': 'Arsenal',
      'away_team': 'Leeds',
      'hot': true,
      'match_time': today.toUtc().toIso8601String(),
      'anchors': [
        {'room_num': 'real-streamer-room'},
      ],
    },
    {
      'source_id': 'schedule-without-room',
      'league': 'Bundesliga',
      'home_team': 'Dortmund',
      'away_team': 'Mainz',
      'match_time': today.toUtc().toIso8601String(),
      'anchors': [],
    },
    {
      'source_id': 'tomorrow',
      'league': 'English Premier League',
      'home_team': 'Chelsea',
      'away_team': 'Bournemouth',
      'match_time': today
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
      'anchors': [
        {'room_num': 'tomorrow-room'},
      ],
    },
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('phone filter controls remain usable with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceMatchFilters(
              controller: controller,
              todayOnly: true,
              leagues: const ['English Premier League', 'Bundesliga'],
              league: null,
              visibleCount: 2,
              onQueryChanged: (_) {},
              onTodayChanged: (_) {},
              onLeagueChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
    expect(find.text('All leagues'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape source search fits above the open keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(812, 375);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await http.runWithClient(
      () async {
        try {
          await tester.pumpWidget(
            const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('source-match-search')));
          tester.view.viewInsets = const FakeViewPadding(bottom: 216);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
      () => MockClient(
        (request) async => request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404),
      ),
    );
  });

  testWidgets('YYZB Today and All dates make upcoming fixtures discoverable', (
    tester,
  ) async {
    final requests = <Uri>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Dortmund'), findsOneWidget);
        expect(find.text('Chelsea'), findsNothing);
        expect(find.text('NOT READY'), findsOneWidget);
        await tester.tap(find.text('NOT READY'));
        await tester.pumpAndSettle();
        expect(requests.every((uri) => uri.path.endsWith('/matches')), isTrue);

        await tester.tap(find.text('All dates'));
        await tester.pumpAndSettle();
        expect(find.text('3 matches'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('source-match-search')),
          'CHELSEA premier',
        );
        await tester.pumpAndSettle();
        expect(find.text('1 match'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);

        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(find.text('0 matches'), findsOneWidget);
        expect(find.text('Chelsea'), findsNothing);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        requests.add(request.url);
        return request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404);
      }),
    );
  });

  testWidgets('searchable league picker filters Today and All dates together', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All leagues'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Search leagues'),
          'premier',
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Bundesliga'), findsNothing);
        await tester.tap(
          find.widgetWithText(ListTile, 'English Premier League'),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 match'), findsOneWidget);
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Dortmund'), findsNothing);

        await tester.tap(find.text('All dates'));
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient(
        (request) async => request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404),
      ),
    );
  });
}
