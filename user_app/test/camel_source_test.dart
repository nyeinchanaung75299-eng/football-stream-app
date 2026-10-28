import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/screens/source_browser_page.dart';

void main() {
  testWidgets(
    'Camel fixtures clearly open provider login instead of pretending to resolve streams',
    (tester) async {
      String? external;
      var streamRequests = 0;
      final previous = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = _Launcher((url) => external = url);
      addTearDown(() => UrlLauncherPlatform.instance = previous);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: SourceBrowserPage(source: 'camel')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Watch on Camel1 • sign-in required'),
            findsOneWidget,
          );
          await tester.tap(find.text('OPEN CAMEL1'));
          await tester.pumpAndSettle();
          expect(
            external,
            'https://www.camel1.tv/football/match-home-vs-away/live/fixture123',
          );
          expect(streamRequests, 0);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/streams')) streamRequests++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'matches': [
                {
                  'source': 'camel',
                  'source_id': 'fixture123',
                  'home_team': 'Home',
                  'away_team': 'Away',
                  'league': 'League',
                  'match_time': DateTime.now()
                      .add(const Duration(hours: 1))
                      .toUtc()
                      .toIso8601String(),
                  'page_url':
                      'https://www.camel1.tv/football/match-home-vs-away/live/fixture123',
                  'anchors': [
                    {'room_num': 'fixture123'},
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );
    },
  );
}

class _Launcher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  _Launcher(this.onOpen);
  final void Function(String) onOpen;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    onOpen(url);
    return true;
  }
}
