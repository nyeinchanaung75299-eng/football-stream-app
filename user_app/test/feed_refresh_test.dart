import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/home_page.dart';
import 'package:football_viewer/screens/source_browser_page.dart';

const match = <String, dynamic>{
  'id': '78953b62-a3b6-42af-9ea8-0ecdc15bd942',
  'home_team': 'Team Alpha',
  'away_team': 'Team Beta',
  'stream_count': 0,
  'stream_links': <Map<String, dynamic>>[],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NCA',
      packageName: 'nca.viewer',
      version: '9.8.0',
      buildNumber: '10545',
      buildSignature: '',
    );
  });

  for (final sourceTab in [false, true]) {
    final label = sourceTab ? 'source tab' : 'Live';
    testWidgets('$label uses a live backup when the primary domain fails', (
      tester,
    ) async {
      final hosts = <String>{};
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: sourceTab
                  ? const SourceBrowserPage(source: 'soco')
                  : const HomePage(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Team Alpha'), findsOneWidget);
          expect(hosts, contains('football-api.nyeinchanaung.us.ci'));
          expect(hosts.length, greaterThan(1));
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (!request.url.path.endsWith('/matches'))
            return http.Response('{}', 404);
          hosts.add(request.url.host);
          if (request.url.host == 'football-api.nyeinchanaung.us.ci') {
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({
              'matches': [match],
            }),
            200,
          );
        }),
      );
    });

    testWidgets(
      '$label retains visible matches after a failed background refresh',
      (tester) async {
        var fail = false;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: sourceTab
                    ? const SourceBrowserPage(source: 'soco')
                    : const HomePage(),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Team Alpha'), findsOneWidget);
            fail = true;
            await tester.pump(const Duration(seconds: 60));
            await tester.pumpAndSettle();
            expect(find.text('Team Alpha'), findsOneWidget);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            if (!request.url.path.endsWith('/matches'))
              return http.Response('{}', 404);
            if (fail) return http.Response('{}', 503);
            return http.Response(
              jsonEncode({
                'matches': [match],
              }),
              200,
            );
          }),
        );
      },
    );

    testWidgets(
      '$label clears previous matches after a successful empty response',
      (tester) async {
        var empty = false;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: sourceTab
                    ? const SourceBrowserPage(source: 'soco')
                    : const HomePage(),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Team Alpha'), findsOneWidget);
            empty = true;
            await tester.pump(const Duration(seconds: 60));
            await tester.pumpAndSettle();
            expect(find.text('Team Alpha'), findsNothing);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            if (!request.url.path.endsWith('/matches'))
              return http.Response('{}', 404);
            return http.Response(
              jsonEncode({
                'matches': empty ? [] : [match],
              }),
              200,
            );
          }),
        );
      },
    );
  }

  for (final requestFails in [false, true]) {
    testWidgets(
      requestFails
          ? 'failed stream lookup preserves the advertised line count'
          : 'successful empty stream lookup clears the advertised line count',
      (tester) async {
        await http.runWithClient(
          () async {
            await tester.pumpWidget(const MaterialApp(home: HomePage()));
            await tester.pumpAndSettle();
            expect(find.text('WATCH LIVE'), findsOneWidget);
            await tester.tap(find.text('WATCH LIVE'));
            await tester.pumpAndSettle();
            if (requestFails) {
              expect(find.text('WATCH LIVE'), findsOneWidget);
              expect(
                find.text(
                  'Could not load lines. Check your connection and try again.',
                ),
                findsOneWidget,
              );
            } else {
              expect(find.text('WATCH LIVE'), findsNothing);
              expect(find.text('NOT READY'), findsOneWidget);
            }
            expect(find.text('Loading lines…'), findsNothing);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            if (request.url.path.endsWith('/matches')) {
              return http.Response(
                jsonEncode({
                  'matches': [
                    {...match, 'stream_count': 1},
                  ],
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/streams')) {
              return http.Response(
                jsonEncode({'streams': []}),
                requestFails ? 503 : 200,
              );
            }
            return http.Response('{}', 404);
          }),
        );
      },
    );
  }
}
