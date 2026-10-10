import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/nca_published_source.dart';
import 'package:football_viewer/screens/home_page.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';

const ncaImport = <String, dynamic>{
  'id': 'nca-stream-1',
  'label': 'TFLIX • TFLIX streams • Server 1 • HLS',
  'stream_type': 'hls',
  'stream_url': 'https://gateway.example/p/one',
  'is_active': true,
};
const otherSource = <String, dynamic>{
  'id': 'cola-1',
  'label': 'ColaTV • Server 1',
  'stream_type': 'hls',
  'stream_url': 'https://gateway.example/p/other',
  'is_active': true,
};
final catalog = <Map<String, dynamic>>[
  {'source_id': 'match:arsenal-leeds', 'home_team': 'Arsenal',
   'away_team': 'Leeds United', 'league': 'Premier League',
   'match_time': '2026-10-10T11:30:00Z'},
  {'source_id': 'match:west-brom-birmingham', 'home_team': 'West Bromwich',
   'away_team': 'Birmingham', 'league': 'Championship',
   'match_time': '2026-10-10T11:30:00Z'},
  {'source_id': 'match:rayo-athletic', 'home_team': 'Rayo Vallecano',
   'away_team': 'Athletic Bilbao', 'league': 'La Liga',
   'match_time': '2026-10-10T12:00:00Z'},
];
const published = <String, dynamic>{
  'id': '1234', 'home_team': 'Arsenal', 'away_team': 'Leeds United',
  'kickoff_at': '2026-10-10T11:30:00Z', 'stream_count': 3,
  'stream_links': <dynamic>[],
};
const unrelated = <String, dynamic>{
  'id': '5678', 'home_team': 'A Different Team',
  'away_team': 'Another Team', 'kickoff_at': '2026-10-10T11:30:00Z',
  'stream_count': 4, 'stream_links': <dynamic>[],
};

http.Response jsonResponse(Object value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)), 200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NCA', packageName: 'nca.viewer', version: '9.8.0',
      buildNumber: '10545', buildSignature: '',
    );
  });

  test('NCA source filter never accepts other providers', () {
    final rows = ncaPublishedLines([ncaImport, otherSource, {
      ...otherSource, 'id': 'yyzb-1', 'label': 'YYZB • TFLIX stream',
    }]);
    expect(rows.length, 1);
    expect(rows.single['label'], 'NCA Server 1');
    expect(rows.single['stream_url'], ncaImport['stream_url']);
  });

  test('catalog keeps ALL fixture cards, only attaches matching NCA streams', () {
    final rows = ncaCatalogWithImportedStreams(catalog, [
      {...published, 'stream_count': 1,
        'stream_links': [ncaPublishedLines([ncaImport]).single]},
      {...unrelated, 'stream_links': [otherSource]},
    ]);
    expect(rows.length, 3);
    expect(rows.map((m) => m['home_team']).toList(),
      ['Arsenal', 'West Bromwich', 'Rayo Vallecano']);
    expect(rows[0]['id'], '1234');
    expect(rows[0]['stream_count'], 1);
    expect(rows[1]['stream_count'], 0);
    expect(rows[2]['stream_count'], 0);
    expect(rows[1]['id'], 'nca:match:west-brom-birmingham');
  });

  test('matches with different kickoff dates cannot borrow a stream', () {
    final rows = ncaCatalogWithImportedStreams(catalog, [
      {...published, 'kickoff_at': '2026-10-13T11:30:00Z',
        'stream_links': [ncaImport]},
    ]);
    expect(rows[0]['stream_count'], 0);
  });

  testWidgets('NCA lists catalog matches whether or not a stream was imported',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(ncaView: true)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('NCA'), findsWidgets);
      expect(find.text('Arsenal'), findsOneWidget);
      expect(find.text('West Bromwich'), findsOneWidget);
      expect(find.textContaining('CHECK NCA STREAM'), findsWidgets);
      expect(find.byType(PremiumBottomNav), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/soco-links') &&
          request.url.queryParameters['source'] == 'nca') {
        return jsonResponse({'source': 'nca', 'matches': catalog});
      }
      if (request.url.path.endsWith('/matches')) {
        return jsonResponse({'matches': [published, unrelated]});
      }
      if (request.url.path.endsWith('/matches/1234/streams')) {
        return jsonResponse({'streams': [ncaImport, otherSource]});
      }
      return http.Response('{}', 404);
    }));
  });


  testWidgets('NCA matches can request automatic stream before manual import',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage(ncaView: true)));
      await tester.pumpAndSettle();
      expect(find.text('Arsenal'), findsOneWidget);
      expect(find.textContaining('CHECK NCA STREAM'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/soco-links') &&
          request.url.queryParameters['source'] == 'nca') {
        return jsonResponse({'source': 'nca', 'matches': catalog});
      }
      if (request.url.path.endsWith('/matches')) {
        return jsonResponse({'matches': []});
      }
      return http.Response('{}', 404);
    }));
  });

  testWidgets('NCA displays the full catalog with zero published streams',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(ncaView: true)));
      await tester.pumpAndSettle();
      expect(find.text('Arsenal'), findsOneWidget);
      expect(find.text('West Bromwich'), findsOneWidget);
      expect(find.textContaining('CHECK NCA STREAM'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/soco-links') &&
          request.url.queryParameters['source'] == 'nca') {
        return jsonResponse({'source': 'nca', 'matches': catalog});
      }
      if (request.url.path.endsWith('/matches')) {
        return jsonResponse({'matches': []});
      }
      return http.Response('{}', 404);
    }));
  });
}
