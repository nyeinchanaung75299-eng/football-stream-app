import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/highlight_source_service.dart';
import 'package:football_viewer/screens/highlight_source_page.dart';
import 'package:football_viewer/widgets/premium_match_card.dart';

class FakeHighlights extends PublicHighlightsService {
  @override
  Future<List<Map<String, dynamic>>> list(int offset) async => [
    {
      'id': 'one',
      'home_team': 'Juventus',
      'away_team': 'Venezia',
      'home_score': 2,
      'away_score': 2,
      'is_finished': true,
      'lines': [],
    },
  ];
}

void main() {
  test('uses the Vercel public RPC without a user session', () async {
    final service = PublicHighlightsService(
      client: MockClient((request) async {
        expect(request.url.host, 'nca25-live-relay.vercel.app');
        expect(request.url.path, '/rest/v1/rpc/viewer_highlight_matches');
        expect(request.url.queryParameters['p_offset'], '25');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response('[]', 200);
      }),
    );
    expect(await service.list(25), isEmpty);
  });

  testWidgets('an archived match shows its score without a playback button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HighlightsSourcePage(service: FakeHighlights())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(PremiumMatchCard), findsOneWidget);
    expect(find.text('2–2 • FT'), findsOneWidget);
    expect(find.text('HIGHLIGHTS NOT READY'), findsOneWidget);
    expect(find.text('WATCH HIGHLIGHTS'), findsNothing);
  });
  testWidgets('HL search filters the shared match-card list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HighlightsSourcePage(service: FakeHighlights())),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Barcelona');
    await tester.pumpAndSettle();
    expect(find.text('No highlights for these filters.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Juventus');
    await tester.pumpAndSettle();
    expect(find.byType(PremiumMatchCard), findsOneWidget);
  });

}
