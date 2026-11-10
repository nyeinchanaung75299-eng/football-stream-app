import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:football_viewer/viewer_tab_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/channels_page.dart';

void main() {
  setUp(() {
    ViewerTabCache.clearForTesting();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'search finds channels beyond the initial viewport without refetching',
    (tester) async {
      var reads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
          await tester.pumpAndSettle();
          expect(find.text('Channel 200'), findsNothing);
          await tester.enterText(find.byType(TextField), 'channel200');
          await tester.pumpAndSettle();
          expect(find.text('Channel 200'), findsOneWidget);
          expect(find.text('Channel 1'), findsNothing);
          expect(reads, 1);
          await tester.enterText(find.byType(TextField), 'no such channel');
          await tester.pumpAndSettle();
          expect(find.text('No matching channels.'), findsOneWidget);
          await tester.tap(find.byTooltip('Clear search'));
          await tester.pumpAndSettle();
          expect(find.text('Channel 1'), findsOneWidget);
          expect(find.text('Channel 200'), findsNothing);
          expect(reads, 1);
        },
        () => MockClient((request) async {
          // EPG is loaded once independently; searching does not re-fetch catalog.
          if (request.url.path.endsWith('/tv-schedule')) {
            return http.Response(jsonEncode({'ok': true, 'channels': []}), 200);
          }
          if (request.url.path.endsWith('/matches')) {
            return http.Response(jsonEncode({'ok': true, 'matches': []}), 200);
          }
          reads++;
          return http.Response(
            jsonEncode({
              'ok': true,
              'channels': List.generate(
                200,
                (i) => {
                  'id': 'id-$i',
                  'name': 'Channel ${i + 1}',
                  'category': 'Sport',
                },
              ),
            }),
            200,
          );
        }),
      );
    },
  );

  testWidgets('cached Channels catalog survives Safari reload and API outage',
      (tester) async {
    const title = 'beIN Sports Test';
    const channelId = '00000000-0000-0000-0000-000000000011';
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final snapshot = prefs.getString('viewer_public_channel_catalog_v2');
      expect(snapshot, isNotNull);
      expect(snapshot, contains(title));
      expect(snapshot, isNot(contains('private-key')));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, () => MockClient((request) async {
      if (request.url.path == '/channels') {
        return http.Response(jsonEncode({
          'ok': true,
          'channels': [{
            'id': channelId,
            'name': title,
            'category': 'Sport',
            'image_url': '',
            'key_data': 'private-key',
          }],
        }), 200);
      }
      return http.Response(jsonEncode({'ok': true, 'channels': [],
        'matches': []}), 200);
    }));

    ViewerTabCache.clearForTesting(); // Memory lost; disk survives.
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text(title), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 503)));
  });

  testWidgets('channel stream network failure offers safe Retry, not raw URL',
      (tester) async {
    const channelId = '00000000-0000-0000-0000-000000000012';
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline Channel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Channel connection failed'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
      expect(find.textContaining('Channel service unavailable'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/streams')) {
        return http.Response('private-server-token', 503);
      }
      if (request.url.path == '/channels') {
        return http.Response(jsonEncode({'ok': true, 'channels': [{
          'id': channelId, 'name': 'Offline Channel', 'category': 'Sport',
        }]}), 200);
      }
      return http.Response(jsonEncode({
        'ok': true, 'channels': [], 'matches': [],
      }), 200);
    }));
  });

  testWidgets(
    'channel logo opens the first protected video directly in portrait',
    (tester) async {
      Map? opened;
      const bridge = MethodChannel('football_stream/native_player');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bridge, (call) async {
            if (call.method == 'openPlayer') opened = call.arguments as Map;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(bridge, null),
      );
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'channel');
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.tap(find.text('Channel'));
          await tester.pumpAndSettle();
          expect(tester.testTextInput.isVisible, isFalse);
          expect(opened, isNotNull);
          final lines = jsonDecode(opened!['sourcesJson'] as String) as List;
          expect(lines.first['portraitStart'], true);
          expect(opened!['selectedIndex'], 0);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('Server 1'), findsNothing);
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/streams')
                  ? {
                      'ok': true,
                      'streams': [
                        {
                          'id': 'one',
                          'stream_url': 'https://play.example/p/token',
                          'protected_proxy': true,
                          'stream_type': 'hls',
                          'label': 'Server 1',
                        },
                      ],
                    }
                  : {
                      'ok': true,
                      'channels': [
                        {
                          'id': '00000000-0000-0000-0000-000000000001',
                          'name': 'Channel',
                          'category': 'Sport',
                        },
                      ],
                    },
            ),
            200,
          ),
        ),
      );
    },
  );

  testWidgets('four channels wrap into two rows at phone and desktop widths', (
    tester,
  ) async {
    for (final width in [390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(key: ValueKey(width), home: const ChannelsPage()),
          );
          await tester.pumpAndSettle();
          final a = tester.getRect(find.text('Channel 1'));
          final b = tester.getRect(find.text('Channel 2'));
          final c = tester.getRect(find.text('Channel 3'));
          final d = tester.getRect(find.text('Channel 4'));
          expect(a.top, b.top);
          expect(c.top, d.top);
          expect(c.top, greaterThan(a.top));
          expect(b.left, greaterThan(a.left));
          expect(c.left, a.left);
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channels': List.generate(
                4,
                (i) => {
                  'id': 'id-$i',
                  'name': 'Channel ${i + 1}',
                  'category': 'Sport',
                },
              ),
            }),
            200,
          ),
        ),
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
