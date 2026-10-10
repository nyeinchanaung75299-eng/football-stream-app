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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NCA', packageName: 'nca.viewer', version: '9.8.0',
      buildNumber: '10545', buildSignature: '',
    );
  });

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

  test('NCA source fence accepts only explicitly imported source provenance', () {
    final rows = ncaPublishedLines([ncaImport, otherSource, {
      ...otherSource, 'id': 'yyzb-1', 'label': 'YYZB • TFLIX stream',
    }]);
    expect(rows.length, 1);
    expect(rows.single['label'], 'NCA Server 1');
    expect(rows.single['stream_url'], ncaImport['stream_url']);
    expect(ncaPublishedLines([otherSource]), isEmpty);
  });

  testWidgets('NCA shows only imported source matches, never Live match lines',
      (tester) async {
    final published = {
      'id': '1234', 'home_team': 'Published Home', 'away_team': 'Published Away',
      'stream_count': 3, 'stream_links': <dynamic>[],
    };
    final unrelated = {
      'id': '5678', 'home_team': 'Unrelated Home', 'away_team': 'Unrelated Away',
      'stream_count': 4, 'stream_links': <dynamic>[],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage(ncaView: true)));
      await tester.pumpAndSettle();
      // NCA performs an extra protected-source metadata lookup after matches.
      // Give the asynchronous HTTP response its own frame before asserting.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('NCA'), findsWidgets);
      expect(find.text('Published Home'), findsOneWidget);
      expect(find.text('Unrelated Home'), findsNothing);
      expect(find.byType(PremiumBottomNav), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/matches')) {
        return http.Response(jsonEncode({'matches': [published, unrelated]}), 200);
      }
      if (request.url.path.endsWith('/matches/1234/streams')) {
        return http.Response(jsonEncode({'streams': [ncaImport, otherSource]}), 200);
      }
      if (request.url.path.endsWith('/matches/5678/streams')) {
        return http.Response(jsonEncode({'streams': [otherSource]}), 200);
      }
      return http.Response('{}', 404);
    }));
  });

  testWidgets('NCA empty state does not borrow ColaTV/YYZB Live matches',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: HomePage(ncaView: true)));
      await tester.pumpAndSettle();
      expect(find.text('No NCA streams yet'), findsOneWidget);
      expect(find.textContaining('Only authorized TFLIX-origin'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/matches')) {
        return http.Response(jsonEncode({'matches': [
          {'id': '5678', 'home_team': 'Not Imported', 'away_team': 'Other',
           'stream_count': 4, 'stream_links': <dynamic>[]},
        ]}), 200);
      }
      if (request.url.path.endsWith('/matches/5678/streams')) {
        return http.Response(jsonEncode({'streams': [otherSource]}), 200);
      }
      return http.Response('{}', 404);
    }));
  });
}
