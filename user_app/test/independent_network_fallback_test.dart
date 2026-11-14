import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_viewer/network_endpoints.dart';
import 'package:football_viewer/repository_logo.dart';
import 'package:football_viewer/screens/channels_page.dart';
import 'package:football_viewer/screens/source_browser_page.dart';
import 'package:football_viewer/viewer_tab_cache.dart';
import 'package:football_viewer/widgets/premium_match_card.dart';

void main() {
  setUp(() {
    ViewerTabCache.clearForTesting();
    SharedPreferences.setMockInitialValues({});
    rememberVerifiedPublicApiBase(cloudflarePublicBase);
  });
  testWidgets(
    'a first Channels visit loads through the independent route while Cloudflare hangs and Vercel is paused',
    (tester) async {
      final hung = <Completer<http.Response>>[];
      var independentReads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: ChannelsPage()));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();
          expect(find.text('Independent Sports'), findsOneWidget);
          expect(independentReads, greaterThan(0));
          await tester.pumpWidget(const SizedBox.shrink());
          for (final pending in hung) {
            pending.complete(http.Response('{}', 503));
          }
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          if (request.url.host == Uri.parse(independentPublicBase).host) {
            independentReads++;
            expect(request.headers['apikey'], viewerPublicApiKey);
            return http.Response(
              jsonEncode({
                'ok': true,
                'channels': request.url.path.endsWith('/channels')
                    ? [
                        {
                          'id': '00000000-0000-0000-0000-000000000001',
                          'name': 'Independent Sports',
                          'category': 'Sport',
                        },
                      ]
                    : [],
                'matches': [],
              }),
              200,
            );
          }
          if (request.url.host == Uri.parse(vercelBackupBase).host)
            return http.Response('DEPLOYMENT_DISABLED', 402);
          final pending = Completer<http.Response>();
          hung.add(pending);
          return pending.future;
        }),
      );
    },
  );
  for (final source in ['repository', 'soco', 'yyzb', 'cola', 'fawa']) {
    testWidgets(
      '$source listing does not stay loading when Cloudflare is unreachable',
      (tester) async {
        final hung = <Completer<http.Response>>[];
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(home: SourceBrowserPage(source: source)),
            );
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pumpAndSettle();
            expect(find.text('Independent Home'), findsOneWidget);
            await tester.pumpWidget(const SizedBox.shrink());
            for (final pending in hung) {
              pending.complete(http.Response('{}', 503));
            }
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            if (request.url.host == Uri.parse(independentPublicBase).host) {
              expect(request.headers['apikey'], viewerPublicApiKey);
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'source': source,
                  'matches': [
                    {
                      'source': source,
                      'source_id': 'repo:match:aaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                      'league': 'Premier League',
                      'home_team': 'Independent Home',
                      'away_team': 'Independent Away',
                      'match_time': DateTime.now()
                          .add(const Duration(hours: 1))
                          .toUtc()
                          .toIso8601String(),
                      'anchors': [
                        {'room_num': 'actual-room'},
                      ],
                    },
                  ],
                }),
                200,
              );
            }
            if (request.url.host == Uri.parse(vercelBackupBase).host)
              return http.Response('DEPLOYMENT_DISABLED', 402);
            final pending = Completer<http.Response>();
            hung.add(pending);
            return pending.future;
          }),
        );
      },
    );
  }
  testWidgets(
    'main Live cards migrate the exact saved Vercel badge URL used by Pick Big Matches',
    (tester) async {
      const old =
          'https://nca-network-backup-test.vercel.app/team-logos/154426';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumMatchCard(
              league: 'UEFA Nations League',
              homeName: 'Kosovo',
              awayName: 'Israel',
              kickoff: null,
              isLive: false,
              canWatch: false,
              actionLabel: 'Not ready',
              onWatch: () {},
              homeLogo: old,
            ),
          ),
        ),
      );
      final urls = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<NetworkImage>()
          .map((image) => image.url);
      expect(urls, contains(independentImageUrl('/team-logos/154426')));
      expect(repositoryLogoUrl(old), independentImageUrl('/team-logos/154426'));
      expect(
        repositoryLogoUrl('$cloudflarePublicBase/team-logos/154426'),
        independentImageUrl('/team-logos/154426'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
