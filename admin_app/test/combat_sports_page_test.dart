import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/combat_sports_page.dart';
import 'package:football_admin/services/connected_channel_source.dart';

class FakeCombat extends ConnectedChannelSource {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> request(String action,
      [Map<String, dynamic> fields = const {}]) async {
    calls.add({'action': action, ...fields});
    final entry = {
      'id': 'combat:fixture',
      'name': 'Fighter A vs Fighter B',
      'event_name': 'UFC fixture',
      'category': 'ufc',
      'category_name': 'UFC',
      'discipline': 'MMA',
      'kickoff_at': null,
      'status': 'unknown',
      'source_names': ['Stream Hub fixture'],
      'stream_count': 1
    };
    return action == 'combat_details'
        ? {
            'entry': {
              ...entry,
              'lines': [
                {
                  'id': 'line',
                  'label': 'HD',
                  'source_name': 'Fixture',
                  'stream_type': 'hls',
                  'stream_url': 'https://combat.example.org/video.m3u8'
                }
              ]
            }
          }
        : {
            'state': {'status': 'partial'},
            'entries': [entry],
            'total': 1
          };
  }
}

void main() {
  testWidgets(
      'Combat filters and lines reuse Hub reads, leave unknown status honest and never trigger sync',
      (tester) async {
    final source = FakeCombat();
    await tester
        .pumpWidget(MaterialApp(home: CombatSportsPage(service: source)));
    await tester.pumpAndSettle();
    expect(find.textContaining('UNKNOWN'), findsWidgets);
    expect(find.text('Time: Unknown'), findsOneWidget);
    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UFC').last);
    await tester.pumpAndSettle();
    expect(source.calls.last['category'], 'ufc');
    await tester.tap(find.text('VIEW LINES'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Video playback has not been verified'),
        findsOneWidget);
    expect(find.text('https://combat.example.org/video.m3u8'), findsOneWidget);
    expect(source.calls.map((x) => x['action']),
        everyElement(isIn(['combat_catalog', 'combat_details'])));
    expect(tester.takeException(), isNull);
  });
}
