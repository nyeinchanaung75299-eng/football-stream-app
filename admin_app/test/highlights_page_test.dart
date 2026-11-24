import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/highlights_page.dart';
import 'package:football_admin/services/highlights_service.dart';

class FakeHighlights extends HighlightsService {
  final requests = <String>[];
  bool fail = false;
  bool noLinks = false;
  bool sourcePageOnly = false;
  final savedLines = <Map<String, dynamic>>[];
  @override
  Future<List<Map<String, dynamic>>> destinations() async => [];

  @override
  Future<void> save(
      Map<String, dynamic> entry, Map<String, dynamic> line, {String? matchId}) async {
    savedLines.add({...line, 'title': entry['title']});
  }

  static final entry = {
    'id': 'one',
    'provider': 'dasfootball',
    'title': 'Home vs Away',
    'lines': [
      {
        'id': 'line',
        'label': 'Highlights',
        'stream_type': 'hls',
        'stream_url': 'https://cdn.example.org/video.m3u8',
        'referer': 'https://example.org/match',
        'origin': 'https://example.org'
      }
    ]
  };
  @override
  Future<Map<String, dynamic>> request(String action,
      [Map<String, dynamic> fields = const {}]) async {
    requests.add(action);
    if (fail) throw StateError('offline');
    if (action == 'check')
      return {
        'check': {'status': 'reachable', 'http': 206, 'ms': 10}
      };
    if (action == 'details')
      return {
        'entry': {
          ...entry,
          if (sourcePageOnly)
            'source_page_only': true,
          if (sourcePageOnly)
            'source_page_url':
                'https://dasfootball.com/match/home-vs-away-2026-11-23-209637/',
          'lines': noLinks || sourcePageOnly ? [] : entry['lines'],
        }
      };
    return {
      'source': 'highlights',
      'provider': 'dasfootball',
      'updated_at': '2026-11-13T07:00:00Z',
      'entries': [entry]
    };
  }
}

class PagedHighlights extends HighlightsService {
  final calls=<Map<String,dynamic>>[];
  @override Future<Map<String,dynamic>> request(String action,[Map<String,dynamic> fields=const {}])async{
    calls.add(fields);final offset=fields['offset'] as int? ?? 0;
    final query=fields['query']?.toString()??'';
    return {'entries':[for(var i=offset==0?0:10;i<(offset==0?12:15);i++){'id':'paged-$i','title':query.isEmpty?'Highlight $i':'$query $i','lines':[]}],
      'has_more':offset==0,'next_offset':offset+12};
  }
}

void main() {
  testWidgets('source pagination deduplicates, stops loading and sends a new search',(tester)async{
    final service=PagedHighlights();
    await tester.pumpWidget(MaterialApp(home:HighlightsPage(service:service)));await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView),const Offset(0,-1800));await tester.pumpAndSettle();
    expect(service.calls.map((x)=>x['offset']),[0,12]);expect(find.textContaining('15 highlights'),findsOneWidget);
    expect(find.text('Load more highlights'),findsNothing);
    await tester.enterText(find.byType(TextField),'arsenal');await tester.pump(const Duration(milliseconds:400));await tester.pumpAndSettle();
    expect(service.calls.last['query'],'arsenal');expect(tester.takeException(),isNull);
  });
  testWidgets('failed refresh retains extracted links and Retry recovers',
      (tester) async {
    final service = FakeHighlights();
    await tester
        .pumpWidget(MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    expect(service.requests, ['catalog']);
    expect(find.text('Home vs Away'), findsOneWidget);
    service.fail = true;
    await tester.tap(find.byTooltip('Refresh highlights'));
    await tester.pumpAndSettle();
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an extraction with no working links keeps metadata and exposes no fallback',
      (tester) async {
    final service = FakeHighlights()..noLinks = true;
    await tester
        .pumpWidget(MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home vs Away'));
    await tester.pumpAndSettle();
    expect(find.text('Home vs Away'), findsOneWidget);
    expect(find.text('Copy URL'), findsNothing);
    expect(find.textContaining('No working direct link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source-only Normal HL opens the existing detector without inventing MP4',
      (tester) async {
    final service = FakeHighlights()..sourcePageOnly = true;
    await tester.pumpWidget(
        MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home vs Away'));
    await tester.pumpAndSettle();
    expect(find.text('Open in Stream Detector'), findsOneWidget);
    expect(find.text('Copy source page URL'), findsOneWidget);
    expect(find.text('Select Stream Quality'), findsNothing);
    expect(find.textContaining('Only save or publish media'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'extract and copy links with headers, without website or video-player actions',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'].toString();
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final service = FakeHighlights();
    await tester
        .pumpWidget(MaterialApp(home: HighlightsPage(service: service)));
    await tester.pumpAndSettle();
    for (final retired in [
      'DarkByte',
      'Hoofoot',
      'Reddit',
      'SoccerFullMatch',
      'ScoreBat',
      'Preview',
      'Open original'
    ]) {
      expect(find.text(retired), findsNothing);
    }
    await tester.tap(find.text('Home vs Away'));
    await tester.pumpAndSettle();
    expect(service.requests, ['catalog', 'details']);
    expect(find.text('Select Stream Quality'), findsOneWidget);
    await tester.tap(find.text('ADD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as a standalone highlight'));
    await tester.pumpAndSettle();
    expect(service.savedLines.single['title'], 'Home vs Away');
    expect(service.savedLines.single['origin'], 'https://example.org');
    expect(find.text('ADDED ✓'), findsOneWidget);
    await tester.tap(find.text('Copy details'));
    await tester.pumpAndSettle();
    expect(
        copied,
        contains(
            'https://cdn.example.org/video.m3u8\nReferer: https://example.org/match\nOrigin: https://example.org'));
    await tester.tap(find.text('Check link'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Link reachable • HTTP 206'), findsOneWidget);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Open original'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
