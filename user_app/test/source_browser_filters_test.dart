import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/screens/source_browser_page.dart';
import 'package:football_viewer/widgets/premium_bottom_nav.dart';
import 'package:football_viewer/widgets/source_match_filters.dart';

class _ClosingMockClient extends MockClient {
  _ClosingMockClient(Future<http.Response> Function(http.Request) handler,
      this.onClosed) : super(handler);
  final VoidCallback onClosed;
  @override
  void close() { onClosed(); super.close(); }
}

List<Map<String, dynamic>> _fixtures() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 23, 59);
  return [
    {
      'source_id': 'today-featured',
      'league': 'English Premier League',
      'home_team': 'Arsenal',
      'away_team': 'Leeds',
      'hot': true,
      'match_time': today.toUtc().toIso8601String(),
      'anchors': [
        {'room_num': 'real-streamer-room'},
      ],
    },
    {
      'source_id': 'schedule-without-room',
      'league': 'Bundesliga',
      'home_team': 'Dortmund',
      'away_team': 'Mainz',
      'match_time': today.toUtc().toIso8601String(),
      'anchors': [],
    },
    {
      'source_id': 'tomorrow',
      'league': 'English Premier League',
      'home_team': 'Chelsea',
      'away_team': 'Bournemouth',
      'match_time': today
          .add(const Duration(days: 1))
          .toUtc()
          .toIso8601String(),
      'anchors': [
        {'room_num': 'tomorrow-room'},
      ],
    },
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Totalsportek lists its own fixtures without inventing kickoff times', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source: 'totalsportek')));
      await tester.pumpAndSettle();
      expect(find.text('Everton'), findsOneWidget);
      expect(find.text('Coventry City'), findsOneWidget);
      expect(tester.widget<SourceMatchFilters>(find.byType(SourceMatchFilters)).showDateChoices, isFalse);
      expect(tester.widget<PremiumBottomNav>(find.byType(PremiumBottomNav)).selectedIndex, 5);
      await tester.tap(find.text('CHECK LINES'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no supported direct video line'), findsOneWidget);
      expect(find.text('Open website'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/streams')) {
        expect(request.url.path, '/sources/totalsportek/streams');
        expect(jsonDecode(request.body)['page_url'],
            'https://totalsportekl.is/Everton-vs-Coventry-City/12345');
        return http.Response(jsonEncode({'source': 'totalsportek', 'streams': [],
          if (request.url.queryParameters['metadata_only']=='1') 'metadata_only': true,
        }), 200);
      }
      expect(request.url.path, '/sources/totalsportek/matches');
      return http.Response(jsonEncode({'source': 'totalsportek', 'matches': [{
        'source': 'totalsportek', 'source_id': '12345', 'league': 'Premier League',
        'home_team': 'Everton', 'away_team': 'Coventry City', 'match_time': null,
        'page_url': 'https://totalsportekl.is/Everton-vs-Coventry-City/12345',
        'anchors': [{'room_num': '12345', 'page_url': 'https://totalsportekl.is/Everton-vs-Coventry-City/12345'}],
      }]}), 200);
    }));
  });

  testWidgets('Spurs search shows countdown immediately then verified Myanmar kickoff without opening video', (tester) async {
    final metadata = Completer<http.Response>();
    var videoRequests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source: 'totalsportek')));
      await tester.pumpAndSettle();
      expect(find.text('Leeds United'), findsOneWidget);
      expect(find.text('3hr 26m from now'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Spurs');
      await tester.pumpAndSettle();
      expect(find.text('Tottenham Hotspur'), findsOneWidget);
      metadata.complete(http.Response(jsonEncode({'metadata_only':true,
        'match_time':'2026-11-07T12:30:00Z'}),200));
      await tester.pumpAndSettle();
      expect(find.text('7:00 PM MMT'), findsOneWidget);
      expect(find.text('3hr 26m from now'), findsNothing);
      expect(videoRequests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/streams')) {
        if (request.url.queryParameters['metadata_only']=='1') return metadata.future;
        videoRequests++;
        return http.Response('{"streams":[]}',200);
      }
      return http.Response(jsonEncode({'matches':[{
        'source':'totalsportek','source_id':'78932','league':'Premier League',
        'home_team':'Leeds United','away_team':'Tottenham Hotspur',
        'match_time':null,'time_label':'3hr 26m from now','countdown_minutes':206,
        'page_url':'https://totalsportekl.is/Leeds-United-vs-Tottenham-Hotspur/78932',
      }]}),200);
    }));
  });

  testWidgets('Totalsportek exposes every published website choice when no native video is available', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source:'totalsportek')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CHECK LINES'));
      await tester.pumpAndSettle();
      expect(find.text('Totalsportek website players (2)'), findsOneWidget);
      expect(find.text('First provider'), findsOneWidget);
      expect(find.text('Second provider'), findsOneWidget);
      expect(find.textContaining('no supported direct video line'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if(request.url.path.endsWith('/streams')) {
        return http.Response(jsonEncode({'streams':[],
          if(request.url.queryParameters['metadata_only']=='1') 'metadata_only':true,
          'external_players':[
            {'label':'First provider','url':'https://first.example.org/event/12345'},
            {'label':'Second provider','url':'https://second.example.org/event/12345'},
          ]}),200);
      }
      return http.Response(jsonEncode({'matches':[{
        'source':'totalsportek','source_id':'12345','league':'Premier League',
        'home_team':'Everton','away_team':'Coventry City',
        'page_url':'https://totalsportekl.is/Everton-vs-Coventry-City/12345',
        'anchors':[{'room_num':'12345'}],
      }]}),200);
    }));
  });

  testWidgets('selected website player resolves only that option and leaves unsupported players available', (tester) async {
    final selected = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source:'totalsportek')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CHECK LINES'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SportsRope'));
      await tester.pumpAndSettle();
      expect(selected.toSet(), {'https://bestropes.st/player.php/fixture'});
      expect(find.text('SportsRope • Main'), findsOneWidget);
      expect(find.text('1 lines'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original-only player'));
      await tester.pumpAndSettle();
      expect(selected.toSet(), {'https://bestropes.st/player.php/fixture', 'https://original.example.org/player'});
      expect(find.text('No direct video link is available from this player right now.'), findsOneWidget);
      expect(find.text('Open original'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/streams')) {
        final body = jsonDecode(request.body) as Map;
        final player = body['player_url']?.toString();
        if (player != null) {
          selected.add(player);
          expect(body['page_url'], 'https://totalsportekl.is/Home-vs-Away/12345');
          return http.Response(jsonEncode({'streams': player.contains('bestropes.st') ? [
            {'label':'SportsRope • Main','stream_url':'https://video.example.org/live.m3u8','stream_type':'hls'},
          ] : [], 'external_players':[]}), 200);
        }
        return http.Response(jsonEncode({'streams':[], 'external_players':[
          {'label':'SportsRope','url':'https://bestropes.st/player.php/fixture'},
          {'label':'Original-only player','url':'https://original.example.org/player'},
        ]}), 200);
      }
      return http.Response(jsonEncode({'matches':[{
        'source':'totalsportek','source_id':'12345','league':'Football',
        'home_team':'Home','away_team':'Away',
        'page_url':'https://totalsportekl.is/Home-vs-Away/12345',
        'anchors':[{'room_num':'12345'}],
      }]}), 200);
    }));
  });

  testWidgets('kickoff lookup is bounded and closing the source ignores pending responses', (tester) async {
    final pending = <Completer<http.Response>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source: 'totalsportek')));
      await tester.pumpAndSettle();
      expect(pending.length, 2);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      for (final request in pending) {
        request.complete(http.Response('{"metadata_only":true,"match_time":"2026-11-07T12:30:00Z"}',200));
      }
      await tester.pumpAndSettle();
      expect(pending.length, 2);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/streams')) {
        expect(request.url.queryParameters['metadata_only'], '1');
        final gate = Completer<http.Response>(); pending.add(gate); return gate.future;
      }
      return http.Response(jsonEncode({'matches':List.generate(40,(i)=>{
        'source':'totalsportek','source_id':'${1000+i}',
        'home_team':'Home $i','away_team':'Away $i','league':'Football',
        'time_label':'3hr 26m from now',
        'page_url':'https://totalsportekl.is/Home-vs-Away/${1000+i}',
      })}),200);
    }));
  });

  testWidgets('timed-out kickoff request closes before fallback and later lookups reuse the working route', (tester) async {
    final blocked = Completer<http.Response>();
    String? badOrigin;
    var badClosed = false;
    var badRequests = 0;
    var replacement = false;
    final goodOrigins = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source:'totalsportek')));
      await tester.pumpAndSettle();
      expect(badRequests, 1);
      await tester.pump(const Duration(seconds:9));
      await tester.pumpAndSettle();
      expect(badClosed, isTrue);
      expect(find.text('7:00 PM MMT'), findsOneWidget);
      replacement = true;
      await tester.tap(find.byTooltip('Refresh matches'));
      await tester.pumpAndSettle();
      expect(find.text('Replacement'), findsOneWidget);
      expect(goodOrigins.length, 2);
      expect(goodOrigins.toSet().length, 1);
      expect(badRequests, 1);
      blocked.complete(http.Response('{"metadata_only":true}',200));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    }, () {
      var wasBlocked = false;
      return _ClosingMockClient((request) async {
        if (request.url.path.endsWith('/streams')) {
          expect(request.url.queryParameters['metadata_only'], '1');
          badOrigin ??= request.url.origin;
          if (request.url.origin == badOrigin) {
            badRequests++; wasBlocked = true; return blocked.future;
          }
          expect(badClosed, isTrue);
          goodOrigins.add(request.url.origin);
          return http.Response('{"metadata_only":true,"match_time":"2026-11-07T12:30:00Z"}',200);
        }
        return http.Response(jsonEncode({'matches':[{
          'source':'totalsportek','source_id':replacement?'1001':'1000',
          'home_team':replacement?'Replacement':'Leeds United','away_team':'Tottenham Hotspur',
          'league':'Premier League','time_label':'3hr 26m from now',
          'page_url':'https://totalsportekl.is/Home-vs-Away/${replacement?1001:1000}',
        }]}),200);
      }, () { if (wasBlocked) badClosed = true; });
    });
  });

  testWidgets('Soco All dates excludes old completed fixtures and labels rooms', (tester) async {
    final now = DateTime.now();
    final feed = [
      {
        'source_id': 'finished-long-ago',
        'league': 'MGL D1',
        'home_team': 'Central Stallions',
        'away_team': 'Deren FC',
        'match_time': now.subtract(const Duration(hours: 8)).toUtc().toIso8601String(),
        'anchors': [
          {'room_num': 'room-a'},
          {'room_num': 'room-b'},
        ],
      },
      {
        'source_id': 'current',
        'league': 'ACL Elite',
        'home_team': 'Pakhtakor',
        'away_team': 'Al Nassr',
        'match_time': now.add(const Duration(hours: 2)).toUtc().toIso8601String(),
        'anchors': [
          {'room_num': 'room-c'},
          {'room_num': 'room-d'},
        ],
      },
    ];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source: 'soco')));
      await tester.pumpAndSettle();
      expect(find.text('1 match'), findsOneWidget);
      expect(find.text('Central Stallions'), findsNothing);
      expect(find.text('Pakhtakor'), findsOneWidget);
      expect(find.textContaining('2 ROOMS'), findsOneWidget);
      expect(find.textContaining('2 SOURCES'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async =>
      request.url.path.endsWith('/matches')
        ? http.Response(jsonEncode({'matches': feed}), 200)
        : http.Response('{}', 404)));
  });

  testWidgets('Soco removes a provider-deleted match after a successful refresh', (tester) async {
    final now = DateTime.now().toUtc();
    final fixture = {
      'source_id': 'provider-deletes-this',
      'league': 'ACL Elite',
      'home_team': 'Pakhtakor',
      'away_team': 'Al Nassr',
      'match_time': now.add(const Duration(hours: 2)).toIso8601String(),
      'anchors': <Map<String,dynamic>>[],
    };
    var current = <Map<String,dynamic>>[fixture];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SourceBrowserPage(source: 'soco')));
      await tester.pumpAndSettle();
      expect(find.text('Pakhtakor'), findsOneWidget);
      current = [];
      await tester.tap(find.byTooltip('Refresh matches'));
      await tester.pumpAndSettle();
      expect(find.text('Pakhtakor'), findsNothing);
      expect(find.text('No Soco matches'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async =>
        request.url.path.endsWith('/matches')
          ? http.Response(jsonEncode({'ok':true,'matches':current}),200)
          : http.Response('{}',404)));
  });

  testWidgets('source categories are shown in one bottom nav only, never as top duplicate buttons',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PremiumBottomNav), findsOneWidget);
      for (final title in ['Soco', 'Fawa', 'ColaTV', 'Channels']) {
        expect(find.descendant(
          of: find.byType(AppBar), matching: find.text(title),
        ), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async =>
        request.url.path.endsWith('/matches')
          ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
          : http.Response('{}', 404)));
  });


  testWidgets('legacy YYZB rows show translated known teams and preserve unknown names', (
    tester,
  ) async {
    final now = DateTime.now();
    final kickoff = DateTime(now.year, now.month, now.day, 23, 59);
    final chineseRows = [
      {
        'source_id': 'fixture-42',
        'league': '德甲',
        'home_team': '帕德博恩',
        'away_team': '斯图加特',
        'match_time': kickoff.toUtc().toIso8601String(),
        'anchors': [
          {'room_num': 'room-7', 'nick_name': '老白聊球'},
        ],
      },
      {
        'source_id': 'fixture-43',
        'league': '未知联赛',
        'home_team': '未知球队',
        'away_team': '球队测试',
        'match_time': kickoff.toUtc().toIso8601String(),
        'anchors': [],
      },
    ];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
        );
        await tester.pumpAndSettle();
        expect(find.text('SC Paderborn 07'), findsOneWidget);
        expect(find.text('VfB Stuttgart'), findsOneWidget);
        // A team without a stream room never appears in the watchable-room
        // catalogue.
        expect(find.text('未知球队'), findsNothing);
        expect(find.text('球队测试'), findsNothing);
        expect(find.text('帕德博恩'), findsNothing);
        expect(find.text('未知联赛'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('source-match-search')),
          'paderborn stuttgart',
        );
        await tester.pumpAndSettle();
        expect(find.text('1 match'), findsOneWidget);
        expect(find.text('SC Paderborn 07'), findsOneWidget);
        expect(find.text('未知球队'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async => request.url.path.endsWith('/matches')
          ? http.Response(jsonEncode({'matches': chineseRows}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'})
          : http.Response('{}', 404)),
    );
  });

  testWidgets('phone filter controls remain usable with enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourceMatchFilters(
              controller: controller,
              todayOnly: true,
              leagues: const ['English Premier League', 'Bundesliga'],
              league: null,
              visibleCount: 2,
              onQueryChanged: (_) {},
              onTodayChanged: (_) {},
              onLeagueChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
    expect(find.text('All leagues'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape source search fits above the open keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(812, 375);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await http.runWithClient(
      () async {
        try {
          await tester.pumpWidget(
            const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('source-match-search')));
          tester.view.viewInsets = const FakeViewPadding(bottom: 216);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
      () => MockClient(
        (request) async => request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404),
      ),
    );
  });

  testWidgets('YYZB shows only watchable rooms across local midnight', (
    tester,
  ) async {
    final requests = <Uri>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Dortmund'), findsNothing);
        expect(find.text('NOT READY'), findsNothing);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('Today'), findsNothing);
        expect(find.text('All dates'), findsNothing);
        expect(find.byKey(const ValueKey('yyzb-streams-only')), findsNothing);
        expect(find.byKey(const ValueKey('yyzb-all-football')), findsNothing);
        expect(requests.every((uri) => uri.path.endsWith('/matches')), isTrue);

        await tester.enterText(
          find.byKey(const ValueKey('source-match-search')),
          'CHELSEA premier',
        );
        await tester.pumpAndSettle();
        expect(find.text('1 match'), findsOneWidget);
        expect(find.text('Chelsea'), findsOneWidget);
        expect(find.text('Arsenal'), findsNothing);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        requests.add(request.url);
        return request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404);
      }),
    );
  });

  testWidgets('YYZB searchable league picker filters watchable rooms', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: SourceBrowserPage(source: 'yyzb')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All leagues'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Search leagues'),
          'premier',
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, 'Bundesliga'), findsNothing);
        await tester.tap(
          find.widgetWithText(ListTile, 'English Premier League'),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 matches'), findsOneWidget);
        expect(find.text('Arsenal'), findsOneWidget);
        expect(find.text('Dortmund'), findsNothing);
        expect(find.text('Chelsea'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient(
        (request) async => request.url.path.endsWith('/matches')
            ? http.Response(jsonEncode({'matches': _fixtures()}), 200)
            : http.Response('{}', 404),
      ),
    );
  });
}
