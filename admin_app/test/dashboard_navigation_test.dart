import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_admin/screens/dashboard_page.dart';
import 'package:football_admin/services/diagnostics_service.dart';

void main() {
  testWidgets(
      'Two bottom tabs keep controls usable and never scan automatically',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requests = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: DashboardPage()));
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(find.text('Pick Big Matches'), findsOneWidget);
      expect(find.text('Refresh monitor'), findsNothing);
      await tester.tap(find.text('System Health').last);
      await tester.pumpAndSettle();
      expect(find.text('Connect services'), findsOneWidget);
      expect(find.text('Pick Big Matches'), findsNothing);
      expect(requests, 0);
      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      expect(find.text('Pick Big Matches'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((_) async {
              requests++;
              return http.Response('{}', 200);
            }));
  });

  test(
      'Service reachability is not reported as a Google Drive connection; reports omit playback credentials',
      () async {
    final methods = <String>[];
    final service = DiagnosticsService(client: MockClient((request) async {
      methods.add(request.method);
      expect(request.headers.containsKey('cache-control'), isFalse);
      if (request.url.host == 'raw.githubusercontent.com') {
        expect(request.url.queryParameters.containsKey('_check'), isTrue);
      }
      final path = request.url.path;
      if (path == '/service-health') {
        return http.Response('''{"results":[
          {"service":"viewer-web","http":200,"reachable":true},
          {"service":"admin-web","http":200,"reachable":true},
          {"service":"google-drive","http":401,"reachable":true},
          {"service":"posthog","http":405,"reachable":true}
        ]}''', 200);
      }
      if (path.endsWith('/streams')) {
        return http.Response(
            '{"streams":[{"stream_url":"https://private.invalid/p/secret-playback-token","drm_key":"fixture-secret-key"}]}',
            200);
      }
      if (path.endsWith('/health')) return http.Response('{"ok":true}', 200);
      if (path == '/matches') {
        return http.Response('[{"id":"fixture-match","stream_count":1}]', 200);
      }
      return http.Response('[]', 200);
    }));
    addTearDown(service.close);
    final results = await service.run(onResult: (_) {});
    expect(results.singleWhere((r) => r.id == 'google-drive').status,
        CheckStatus.notConfigured);
    expect(results.singleWhere((r) => r.id == 'supabase').status,
        CheckStatus.failed); // No session must never look like Admin access.
    expect(results.singleWhere((r) => r.id == 'viewer-feed').status,
        CheckStatus.ok);
    final report = results.map((r) => r.toJson()).toString();
    expect(report.contains('secret-playback-token'), isFalse);
    expect(report.contains('fixture-secret-key'), isFalse);
    expect(methods.every((method) => method == 'GET'), isTrue);
  });
}
