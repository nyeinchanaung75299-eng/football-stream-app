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
