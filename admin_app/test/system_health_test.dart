import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/system_health_page.dart';
import 'package:football_admin/services/system_monitor_service.dart';

Map<String, dynamic> fixture() => {
      'version': 1,
      'generatedAt': '2026-10-09T04:00:00Z',
      'windowHours': 24,
      'services': [
        {
          'id': 'posthog',
          'state': 'warning',
          'detail': 'Actual captured data',
          'collectedAt': '2026-10-09T04:00:00Z',
          'events': [
            {'event': r'$exception', 'count': 3, 'affectedUsers': 2}
          ],
          'timing': {
            'state': 'ok',
            'note': 'Measured durations from updated clients.',
            'rows': [
              {
                'event': 'playback started',
                'phase': 'unclassified',
                'app': 'nca_user',
                'platform': 'web',
                'samples': 8,
                'p50Ms': 1300,
                'p95Ms': 4800,
              },
              {
                'event': 'playback buffering ended',
                'phase': 'rebuffer',
                'app': 'nca_user',
                'platform': 'android',
                'samples': 2,
                'p50Ms': 600,
                'p95Ms': 1200,
              },
            ],
          },
          'issues': [
            {
              'title': 'Error fixture',
              'count': 3,
              'affectedUsers': 2,
              'stack': 'sensitive-stack',
              'issue': 'sensitive-issue-id'
            }
          ]
        },
        {
          'id': 'cloudflare',
          'state': 'not_configured',
          'detail': 'Connect read access.'
        },
        {
          'id': 'github',
          'state': 'ok',
          'detail': 'Latest runs',
          'runs': [
            {
              'workflow': 'deploy-web.yml',
              'state': 'in_progress',
              'sha': 'fixture-sha'
            }
          ]
        },
      ],
      'streams': {
        'counts': {'healthy': 1, 'alerts': 1},
        'total': 2,
        'truncated': false,
        'note': 'Alerts only',
        'sources': [],
        'lines': [
          {
            'label': 'Server 3',
            'type': 'DASH',
            'health': 'failed',
            'alert': true,
            'consecutiveFailures': 3,
            'match': 'Team A vs Team B'
          }
        ],
      },
    };
void main() {
  testWidgets('Connecting PostHog after scrolling keeps the report visible',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var connected = false;
    var includeIssues = false;
    Future<Map<String, dynamic>> load() async {
      final data = fixture();
      final posthog = (data['services'] as List).first as Map;
      if (connected) {
        posthog['breakdown'] = [
          {
            'app': 'nca_admin',
            'platform': 'web',
            'event': 'admin function failed',
            'count': 1,
            'affectedUsers': 1,
          }
        ];
        posthog['issues'] = includeIssues
            ? [
                for (final name in ['A', 'B'])
                  {
                    'issue': 'issue-$name',
                    'title': 'Error $name',
                    'count': 1,
                    'affectedUsers': 1,
                    'stack': 'stack-$name',
                  }
              ]
            : [];
      } else {
        posthog['state'] = 'not_configured';
        posthog.remove('events');
        posthog.remove('issues');
        posthog.remove('timing');
      }
      return data;
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SystemHealthPage(active: true, loader: load))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pumpAndSettle();
    final listContext = tester.element(find.byType(ListView).first);
    final bucket = PageStorage.of(listContext);
    expect(bucket.readState(listContext), isA<double>());

    connected = true;
    await tester.tap(find.text('Refresh monitor'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Loading / playback timing'));
    await tester.tap(find.text('Loading / playback timing'));
    await tester.pumpAndSettle();
    expect(find.text('Video startup'), findsOneWidget);
    expect(find.text('Buffering during playback'), findsOneWidget);
    expect(find.textContaining('Median: 1300 ms'), findsOneWidget);
    expect(bucket.readState(listContext), isA<double>());
    expect(tester.takeException(), isNull);
    expect(find.text('App / platform breakdown'), findsOneWidget);
    await tester.ensureVisible(find.text('App / platform breakdown'));
    await tester.tap(find.text('App / platform breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('nca_admin · web'), findsOneWidget);
    expect(tester.takeException(), isNull);
    includeIssues = true;
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh monitor'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Error A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error A'));
    await tester.pumpAndSettle();
    expect(find.text('stack-A'), findsOneWidget);
    expect(find.text('stack-B'), findsNothing);
    await tester.ensureVisible(find.text('Error B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Error B'));
    await tester.pumpAndSettle();
    expect(find.text('stack-A'), findsOneWidget);
    expect(find.text('stack-B'), findsOneWidget);
    expect(bucket.readState(listContext), isA<double>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets(
      'Inactive monitor does not load; opening it displays actual counts and missing access',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    Future<Map<String, dynamic>> load() async {
      calls++;
      return fixture();
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SystemHealthPage(active: false, loader: load))));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SystemHealthPage(active: true, loader: load))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('affected users: 2'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('NOT CONFIGURED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 1);
  });
  test(
      'Report exports retain aggregate counts but omit stack/context/session identifiers',
      () {
    final json = SystemMonitorService.reportJson(fixture());
    final csv = SystemMonitorService.reportCsv(fixture());
    expect(json, contains('"affectedUsers": 2'));
    expect(csv, contains('"posthog"'));
    expect(json, contains('"p95Ms": 4800'));
    expect(csv, contains('playback started unclassified nca_user web p50 ms'));
    expect(csv,
        contains('playback buffering ended rebuffer nca_user android samples'));
    for (final secret in [
      'sensitive-stack',
      'sensitive-issue-id',
      'Server 3'
    ]) {
      expect(json, isNot(contains(secret)));
      expect(csv, isNot(contains(secret)));
    }
  });
}
