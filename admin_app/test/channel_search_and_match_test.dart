import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:football_admin/screens/channels_page.dart';
import 'package:football_admin/screens/live_links_page.dart';

void main() {
  var channelReads = 0;
  var noActiveLine = false;
  final writes = <Map<String, dynamic>>[];
  const channels = [
    {
      'id': 'bein',
      'name': 'BEIN SPORTS 1',
      'category': 'Sport',
      'is_active': true
    },
    {'id': 'fox', 'name': 'FOX SPORTS', 'category': 'Sport', 'is_active': true},
    {'id': 'tnt', 'name': 'Tnt 3', 'category': 'Sport', 'is_active': false},
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.example',
      publishableKey: 'test-public',
      httpClient: MockClient((request) async {
        Object data = [];
        if (request.url.path.endsWith('/channels')) {
          channelReads++;
          data = channels;
        } else if (request.url.path.endsWith('/channel_lines')) {
          data = noActiveLine
              ? []
              : [
                  {
                    'stream_url':
                        'https://origin.example/canonical.mpd?token=fixture',
                    'stream_type': 'dash',
                    'referer': 'https://player.example/watch',
                    'origin': 'https://player.example',
                    'key_id': '00112233445566778899aabbccddeeff',
                    'key_data': 'ffeeddccbbaa99887766554433221100',
                  }
                ];
        } else if (request.url.path.endsWith('/matches')) {
          data = [
            {
              'id': 'match-1',
              'home_team': 'Home',
              'away_team': 'Away',
              'league': 'League',
              'kickoff_at': '2026-10-29T12:00:00Z',
              'is_active': true,
              'is_featured': true,
              'publish_state': 'published'
            }
          ];
        } else if (request.method == 'POST' &&
            request.url.path.endsWith('/stream_links')) {
          writes
              .add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        }
        return http.Response(jsonEncode(data), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
      authOptions: const FlutterAuthClientOptions(
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUri: false),
    );
  });
  setUp(() {
    channelReads = 0;
    noActiveLine = false;
    writes.clear();
  });
  tearDownAll(() async => Supabase.instance.dispose());
  void tallPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  String value(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;
  Future<void> save(WidgetTester tester) async {
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('SAVE LINK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE LINK'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single['match_id'], 'match-1');
    expect(writes.single['stream_url'],
        'https://origin.example/canonical.mpd?token=fixture');
    expect(writes.single['stream_type'], 'dash');
    expect(writes.single['referer'], 'https://player.example/watch');
    expect(writes.single['origin'], 'https://player.example');
    expect(writes.single['key_id'], '00112233445566778899aabbccddeeff');
    expect(writes.single['key_data'], 'ffeeddccbbaa99887766554433221100');
  }

  testWidgets(
      'Admin search filters hidden and visible channels without extra reads',
      (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tnt3');
    await tester.pumpAndSettle();
    expect(find.text('Tnt 3'), findsOneWidget);
    expect(find.text('FOX SPORTS'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nothing matches');
    await tester.pumpAndSettle();
    expect(find.text('No matching channels.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('FOX SPORTS'), findsOneWidget);
    expect(channelReads, 1);
  });

  testWidgets(
      'Channels Add to match keeps the selected channel through match selection',
      (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(ListTile, 'FOX SPORTS');
    await tester.tap(find.descendant(
        of: row, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to match'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a match for FOX SPORTS'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(value(tester, 'Resolution'), 'FOX SPORTS');
    await save(tester);
    expect(writes.single['label'], 'FOX SPORTS');
  });

  testWidgets(
      'Match channel picker searches and replaces stale WebView/DRM settings',
      (tester) async {
    tallPhone(tester);
    await tester.pumpWidget(
        const MaterialApp(home: LiveLinksPage(initialMatchId: 'match-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use WebView'));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('USE CHANNEL'));
    await tester.tap(find.text('USE CHANNEL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bein1');
    await tester.pumpAndSettle();
    expect(find.text('FOX SPORTS'), findsNothing);
    await tester.tap(find.text('BEIN SPORTS 1'));
    await tester.pumpAndSettle();
    expect(value(tester, 'Resolution'), 'BEIN SPORTS 1');
    expect(value(tester, 'keyID'), '00112233445566778899aabbccddeeff');
    expect(value(tester, 'keyData'), 'ffeeddccbbaa99887766554433221100');
    expect(value(tester, 'WebView'), isEmpty);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    await save(tester);
    expect(writes.single['use_webview'], isFalse);
  });

  testWidgets(
      'an empty channel stays in the picker and cancellation preserves the form',
      (tester) async {
    tallPhone(tester);
    noActiveLine = true;
    await tester.pumpWidget(const MaterialApp(
        home: LiveLinksPage(
            initialMatchId: 'match-1',
            initialStreamUrl: 'https://old.example/live.m3u8')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USE CHANNEL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BEIN SPORTS 1'));
    await tester.pumpAndSettle();
    expect(find.text('Choose channel'), findsOneWidget);
    expect(
        find.text('Could not load this channel. Try another channel or retry.'),
        findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(value(tester, 'Link'), 'https://old.example/live.m3u8');
    expect(writes, isEmpty);
  });
}
