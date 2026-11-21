import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/live_links_page.dart';

void main() {
  Completer<http.Response>? pending;
  Map<String, dynamic>? posted;
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
          if (request.method == 'POST' &&
              request.url.path.endsWith('/stream_links')) {
            posted = Map<String, dynamic>.from(jsonDecode(request.body));
            if (pending != null) {
              final delayed = await pending!.future;
              return http.Response.bytes(delayed.bodyBytes, delayed.statusCode,
                  headers: delayed.headers, request: request);
            }
          }
          final data = request.url.path.endsWith('/matches')
              ? [
                  for (final pair in [
                    ['match-a', 'Alpha'],
                    ['match-b', 'Beta']
                  ])
                    {
                      'id': pair[0],
                      'home_team': pair[1],
                      'away_team': 'Visitors',
                      'league': 'Review',
                      'kickoff_at': DateTime.now().toUtc().toIso8601String(),
                      'is_active': true,
                      'is_featured': true,
                      'publish_state': 'published'
                    }
                ]
              : [];
          return http.Response(jsonEncode(data), 200,
              request: request, headers: {'content-type': 'application/json'});
        }));
  });
  tearDownAll(() async => Supabase.instance.dispose());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-a')));
    await tester.pumpAndSettle();
  }

  Future<void> changeMatch(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
  }

  testWidgets('review draft isolation between two match destinations',
      (tester) async {
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Link'),
        'https://cdn.example/match-a.m3u8');
    await changeMatch(tester);
    final after = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Link'))
        .controller!
        .text;
    expect(after, isEmpty);
  });
  testWidgets(
      'review late save completion after changing match and entering a new draft',
      (tester) async {
    pending = Completer<http.Response>();
    await open(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Link'),
        'https://cdn.example/match-a.m3u8');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SAVE LINK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE LINK'));
    await tester.pump();
    expect(posted?['match_id'], 'match-a');
    await changeMatch(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Link'),
        'https://cdn.example/new-match-b.m3u8');
    pending!.complete(http.Response('[]', 201,
        headers: {'content-type': 'application/json'}));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final after = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Link'))
        .controller!
        .text;
    expect(after, 'https://cdn.example/new-match-b.m3u8');
    expect(find.text('Server added.'), findsNothing);
  });
}
