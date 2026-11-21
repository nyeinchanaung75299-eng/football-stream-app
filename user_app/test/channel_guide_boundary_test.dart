import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/channels_page.dart';
import 'package:football_viewer/viewer_tab_cache.dart';
import 'package:football_viewer/channel_match_search.dart';

void main() {
  testWidgets(
    'programme end clears LIVE locally without an extra guide request',
    (tester) async {
      ViewerTabCache.clearForTesting();
      SharedPreferences.setMockInitialValues({});
      Map<String, dynamic>? programme;
      var epgReads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
          await tester.pumpAndSettle();
          expect(find.textContaining('LIVE •'), findsOneWidget);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 3)),
          );
          await tester.pump(const Duration(seconds: 3));
          expect(find.textContaining('LIVE •'), findsNothing);
          expect(epgReads, 1);
          print(
            jsonEncode({
              'review': 'Viewer channel guide boundary',
              'programmeEnded': !currentFootballProgramme(programme!),
              'liveLabelStillVisible': find
                  .textContaining('LIVE •')
                  .evaluate()
                  .isNotEmpty,
              'epgReads': epgReads,
            }),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/channels'))
            return http.Response(
              jsonEncode({
                'ok': true,
                'channels': [
                  {
                    'id': 'epg-review',
                    'name': 'EPG review channel',
                    'category': 'Sport',
                    'image_url': '',
                  },
                ],
              }),
              200,
            );
          if (r.url.path.endsWith('/tv-schedule')) {
            epgReads++;
            final now = DateTime.now().toUtc();
            programme = {
              'title': 'Live Football: Home vs Away',
              'start': now
                  .subtract(const Duration(seconds: 30))
                  .millisecondsSinceEpoch,
              'end': now.add(const Duration(seconds: 2)).millisecondsSinceEpoch,
            };
            return http.Response(
              jsonEncode({
                'ok': true,
                'channels': [
                  {
                    'id': 'epg-review',
                    'matchedEPG': true,
                    'programmes': [programme],
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'ok': true, 'channels': [], 'matches': []}),
            200,
          );
        }),
      );
    },
  );
}
