import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/highlights_page.dart';
import 'package:football_admin/services/highlights_service.dart';

class FakeHighlights extends HighlightsService {
  final requests = <String>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> request(String provider, String action, [Map<String, dynamic> fields = const {}]) async {
    requests.add('$provider:$action');
    if (fail) throw StateError('offline');
    if (action == 'check') return {'check': {'status': 'reachable', 'http': 206, 'ms': 10}};
    return {'source': 'highlights', 'provider': provider, 'updated_at': '2026-11-13T07:00:00Z', 'entries': [
      {'id': 'one', 'provider': provider, 'title': 'Home vs Away', 'source_page_url': 'https://example.org/match', 'lines': [
        {'id': 'line', 'label': 'Highlights', 'stream_type': 'hls', 'stream_url': 'https://cdn.example.org/video.m3u8',
          'referer': 'https://example.org/match', 'origin': 'https://example.org'}
      ]},
    ]};
  }
}

void main() {
  testWidgets('source re-entry reuses data; failed refresh keeps rows and offers Retry', (tester) async {
    final service = FakeHighlights();
    await tester.pumpWidget(MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    expect(service.requests, ['darkbyte:catalog']);
    expect(find.text('Home vs Away'), findsOneWidget);
    await tester.tap(find.text('DasFootball')); await tester.pumpAndSettle();
    await tester.tap(find.text('DarkByte')); await tester.pumpAndSettle();
    expect(service.requests, ['darkbyte:catalog', 'dasfootball:catalog']);
    service.fail = true;
    await tester.tap(find.byTooltip('Refresh highlights')); await tester.pumpAndSettle();
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy includes playback headers; reachable is never reported as verified playback', (tester) async {
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
    await tester.tap(find.text('Home vs Away')); await tester.pumpAndSettle();
    await tester.tap(find.text('Copy details')); await tester.pumpAndSettle();
    expect(copied, contains('https://cdn.example.org/video.m3u8\nReferer: https://example.org/match\nOrigin: https://example.org'));
    await tester.tap(find.text('Check')); await tester.pumpAndSettle();
    expect(find.textContaining('Reachable • HTTP 206'), findsOneWidget);
    expect(find.textContaining('Video not verified'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
