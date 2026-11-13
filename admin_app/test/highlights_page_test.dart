import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/highlights_page.dart';
import 'package:football_admin/services/highlights_service.dart';

class FakeHighlights extends HighlightsService {
  final requests = <String>[];
  bool fail = false;
  bool noLinks = false;
  static final entry = {'id': 'one', 'provider': 'dasfootball', 'title': 'Home vs Away', 'lines': [
    {'id': 'line', 'label': 'Highlights', 'stream_type': 'hls', 'stream_url': 'https://cdn.example.org/video.m3u8',
      'referer': 'https://example.org/match', 'origin': 'https://example.org'}
  ]};
  @override
  Future<Map<String, dynamic>> request(String action, [Map<String, dynamic> fields = const {}]) async {
    requests.add(action);
    if (fail) throw StateError('offline');
    if (action == 'check') return {'check': {'status': 'reachable', 'http': 206, 'ms': 10}};
    if (action == 'details') return {'entry': noLinks ? {...entry, 'lines': []} : entry};
    return {'source': 'highlights', 'provider': 'dasfootball', 'updated_at': '2026-11-13T07:00:00Z', 'entries': [entry]};
  }
}

void main() {
  testWidgets('failed refresh retains extracted links and Retry recovers', (tester) async {
    final service = FakeHighlights();
    await tester.pumpWidget(MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    expect(service.requests, ['catalog']);
    expect(find.text('Home vs Away'), findsOneWidget);
    service.fail = true;
    await tester.tap(find.byTooltip('Refresh highlights')); await tester.pumpAndSettle();
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Retry')); await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an extraction with no working links removes that row and exposes no fallback', (tester) async {
    final service = FakeHighlights()..noLinks = true;
    await tester.pumpWidget(MaterialApp(home: HighlightsPage(service: service))); await tester.pumpAndSettle();
    await tester.tap(find.text('Home vs Away')); await tester.pumpAndSettle();
    expect(find.text('Home vs Away'), findsNothing);
    expect(find.text('Copy URL'), findsNothing);
    expect(find.textContaining('No working direct link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extract and copy links with headers, without website or video-player actions', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'].toString();
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final service = FakeHighlights();
    await tester.pumpWidget(MaterialApp(home: HighlightsPage(service: service))); await tester.pumpAndSettle();
    for (final retired in ['DarkByte', 'Hoofoot', 'Reddit', 'SoccerFullMatch', 'ScoreBat', 'Preview', 'Open original']) {
      expect(find.text(retired), findsNothing);
    }
    await tester.tap(find.text('Home vs Away')); await tester.pumpAndSettle();
    expect(service.requests, ['catalog', 'details']);
    await tester.tap(find.text('Copy details')); await tester.pumpAndSettle();
    expect(copied, contains('https://cdn.example.org/video.m3u8\nReferer: https://example.org/match\nOrigin: https://example.org'));
    await tester.tap(find.text('Check link')); await tester.pumpAndSettle();
    expect(find.textContaining('Link reachable • HTTP 206'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Open original'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
