import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  testWidgets('NCA tab only lists published matches with Admin stream lines',
      (tester) async {
    final published = {
      'id': '1234',
      'home_team': 'Published Home',
      'away_team': 'Published Away',
      'stream_count': 2,
      'stream_links': <dynamic>[],
    };
    final unlinked = {
      'id': '5678',
      'home_team': 'No Link Home',
      'away_team': 'No Link Away',
      'stream_count': 0,
      'stream_links': <dynamic>[],
    };
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(ncaView: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('NCA'), findsWidgets);
      expect(find.text('Published Home'), findsOneWidget);
      expect(find.text('No Link Home'), findsNothing);
      expect(find.byType(PremiumBottomNav), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/matches')) {
        return http.Response(jsonEncode({'matches': [published, unlinked]}), 200);
      }
      return http.Response('{}', 404);
    }));
  });

  testWidgets('NCA has an empty state when Admin has published no servers',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(ncaView: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No NCA streams yet'), findsOneWidget);
      expect(find.textContaining('Publish an authorized stream'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/matches')) {
        return http.Response(jsonEncode({'matches': [
          {'id': '1234', 'home_team': 'Not Streamed', 'away_team': 'Other',
           'stream_count': 0, 'stream_links': <dynamic>[]},
        ]}), 200);
      }
      return http.Response('{}', 404);
    }));
  });
}
