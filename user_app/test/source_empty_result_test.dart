import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/source_browser_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final provider in ['tflix', 'streame']) {
    testWidgets(
      '$provider empty verification stops alias retries and allows retry',
      (tester) async {
        var lookups = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(home: SourceBrowserPage(source: provider)),
            );
            await tester.pumpAndSettle();
            for (var attempt = 1; attempt <= 2; attempt++) {
              await tester.ensureVisible(find.text('WATCH'));
              await tester.tap(find.text('WATCH'));
              await tester.pumpAndSettle();
              expect(
                lookups,
                attempt,
                reason: 'An empty verified result must not scan every alias.',
              );
              expect(find.text('Loading lines…'), findsNothing);
              expect(
                find.textContaining(provider == 'tflix'
                    ? 'No app-compatible TFLIX stream is available.'
                    : 'stream is available now.'),
                findsOneWidget,
              );
              await tester.pump(const Duration(seconds: 5));
              await tester.pumpAndSettle();
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            if (request.url.path.endsWith('/streams')) {
              lookups++;
              return http.Response(jsonEncode({'streams': []}), 200);
            }
            return http.Response(
              jsonEncode({
                'source': provider,
                'matches': [
                  {
                    'source_id': 'match:fixture',
                    'league': 'Fixture league',
                    'home_team': 'Team Alpha',
                    'away_team': 'Team Beta',
                    'match_time': DateTime.now().toUtc().toIso8601String(),
                  },
                ],
              }),
              200,
            );
          }),
        );
      },
    );
  }
}
