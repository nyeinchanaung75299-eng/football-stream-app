import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/live_links_page.dart';

void main() {
  bool rowExists = true;
  var updates = 0;
  bool simulateFailure = false;
  setUp(() {
    rowExists = true;
    updates = 0;
    simulateFailure = false;
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://fixture.example',
        publishableKey: 'test-public',
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false),
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH') {
            if (simulateFailure)
              return http.Response(
                  jsonEncode({
                    'message': 'simulated save failure',
                    'code': 'TEST_FAILURE'
                  }),
                  400,
                  request: request,
                  headers: {'content-type': 'application/json'});
            expect(rowExists, false);
            updates++;
            return http.Response('', 204,
                request: request, headers: {'content-range': '*/0'});
          }
          final data = request.url.path.endsWith('/matches')
              ? [
                  {
                    'id': 'match-a',
                    'home_team': 'Alpha',
                    'away_team': 'Visitors',
                    'kickoff_at': DateTime.now().toUtc().toIso8601String(),
                    'is_active': true,
                    'is_featured': true,
                    'publish_state': 'published'
                  }
                ]
              : rowExists
                  ? [
                      {
                        'id': 'line-1',
                        'label': 'Existing line',
                        'stream_url': 'https://cdn.example/live.m3u8',
                        'stream_type': 'hls',
                        'is_active': true,
                        'health_status': 'unknown'
                      }
                    ]
                  : [];
          return http.Response(jsonEncode(data), 200,
              request: request, headers: {'content-type': 'application/json'});
        }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets('review successful edit notice when no row was updated',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-a')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Server actions'));
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Server name'), 'Edited line');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    rowExists = false;
    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.text('Server updated.'), findsNothing);
    expect(find.text('Edit Server'), findsOneWidget);
  });
  testWidgets('review draft retention after server edit fails', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-a')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Server actions'));
    await tester.tap(find.byTooltip('Server actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Server name'), 'Unsaved changed line');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    simulateFailure = true;
    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Save was not confirmed.'), findsOneWidget);
    expect(find.text('Edit Server'), findsOneWidget);
    expect(find.text('Unsaved changed line'), findsOneWidget);
  });
}
