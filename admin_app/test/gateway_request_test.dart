import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:football_admin/services/gateway_request.dart';

void main() {
  test('successful responses stop failover, even for mutations', () async {
    var sent = 0;
    var direct = 0;
    final result = await GatewayRequest(
      bases: ['https://first.test', 'https://second.test'],
      send: (_, __, ___) async {
        sent++;
        return http.Response('{"ok":true}', 200);
      },
      refresh: () async => null,
      direct: () async {
        direct++;
        return {};
      },
    ).run('system-monitor', 'test-token', body: {'action': 'connect'});
    expect(result.base, 'https://first.test');
    expect(result.data, {'ok': true});
    expect(sent, 1);
    expect(direct, 0);
  });

  test('an uncertain write is never replayed on another route', () async {
    var sent = 0;
    var direct = 0;
    final pending = Completer<http.Response>();
    final request = GatewayRequest(
      bases: ['https://first.test', 'https://second.test'],
      totalTimeout: const Duration(milliseconds: 30),
      send: (_, __, ___) {
        sent++;
        return pending.future;
      },
      refresh: () async => null,
      direct: () async {
        direct++;
        return {};
      },
    ).run('system-monitor', 'test-token', body: {'action': 'connect'});
    await expectLater(request, throwsA(isA<StateError>()));
    pending.complete(http.Response('{"ok":true}', 200));
    expect(sent, 1);
    expect(direct, 0);
  });

  test('metadata can fail over sequentially to a healthy route', () async {
    final called = <String>[];
    final result = await GatewayRequest(
      bases: ['https://blocked.test', 'https://backup.test'],
      send: (uri, _, __) async {
        called.add(uri.host);
        if (uri.host == 'blocked.test') {
          throw http.ClientException('Blocked test transport');
        }
        return http.Response('{"matches":[]}', 200);
      },
      refresh: () async => null,
      direct: () async => throw StateError('Direct must not be used'),
    ).run('source-match-list', 'test-token');
    expect(called, ['blocked.test', 'backup.test']);
    expect(result.base, 'https://backup.test');
  });

  test(
    'source catalog rejects a mismatched provider and uses next route',
    () async {
      final called = <String>[];
      final fallbacks = <String>[];
      final result = await GatewayRequest(
        bases: ['https://stale.test', 'https://current.test'],
        send: (uri, _, __) async {
          called.add(uri.host);
          if (uri.host == 'stale.test') {
            return http.Response(
              '{"source":"soco","matches":[{"source":"soco","source_id":"wrong-room"}]}',
              200,
            );
          }
          return http.Response(
            '{"source":"cola","matches":[{"source":"cola","source_id":"right-event"}]}',
            200,
          );
        },
        refresh: () async => null,
        direct: () async => throw StateError('Direct must not be used'),
        onFallback: fallbacks.add,
      ).run('source-match-list', 'test-token', body: {'source': 'cola'});

      expect(called, ['stale.test', 'current.test']);
      expect(fallbacks, ['gateway_source_mismatch']);
      expect(result.base, 'https://current.test');
      expect(result.data['source'], 'cola');
    },
  );

  test(
    'source catalog rejects rows belonging to a different provider',
    () async {
      var direct = 0;
      final result = await GatewayRequest(
        bases: ['https://mixed.test'],
        send: (_, __, ___) async => http.Response(
          '{"source":"cola","matches":[{"source":"soco","source_id":"wrong-room"}]}',
          200,
        ),
        refresh: () async => null,
        direct: () async {
          direct++;
          return {
            'source': 'cola',
            'matches': [
              {'source': 'cola', 'source_id': 'right-event'},
            ],
          };
        },
      ).run('source-match-list', 'test-token', body: {'source': 'cola'});

      expect(result.base, isNull);
      expect(result.data['source'], 'cola');
      expect(direct, 1);
    },
  );

  test('direct fallback rejects data for a different source', () async {
    final request = GatewayRequest(
      bases: const [],
      send: (_, __, ___) async => throw StateError('No gateway route'),
      refresh: () async => null,
      direct: () async => {
        'source': 'soco',
        'matches': <Map<String, dynamic>>[],
      },
    ).run('source-match-list', 'test-token', body: {'source': 'cola'});

    await expectLater(
      request,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('different stream source'),
        ),
      ),
    );
  });

  test('stream resolver rejects a response from another provider', () async {
    final fallbacks = <String>[];
    final result =
        await GatewayRequest(
          bases: ['https://stale.test', 'https://current.test'],
          send: (uri, _, __) async => uri.host == 'stale.test'
              ? http.Response('{"source":"soco","lines":[]}', 200)
              : http.Response('{"source":"cola","lines":[]}', 200),
          refresh: () async => null,
          direct: () async => throw StateError('Direct must not be used'),
          onFallback: fallbacks.add,
        ).run(
          'soco-links',
          'test-token',
          body: {'source': 'cola', 'room_num': 'event-1'},
        );

    expect(result.base, 'https://current.test');
    expect(result.data['source'], 'cola');
    expect(fallbacks, ['gateway_source_mismatch']);
  });

  test('timeouts on multiple routes consume one global budget', () async {
    final pending = Completer<http.Response>();
    final budgets = <Duration>[];
    var direct = 0;
    final request = GatewayRequest(
      bases: [
        'https://first.test',
        'https://second.test',
        'https://third.test',
      ],
      totalTimeout: const Duration(milliseconds: 75),
      routeTimeout: const Duration(milliseconds: 45),
      send: (_, __, timeout) {
        budgets.add(timeout);
        return pending.future;
      },
      refresh: () async => null,
      direct: () async {
        direct++;
        return {};
      },
    ).run('source-match-list', 'test-token');
    await expectLater(request, throwsA(isA<TimeoutException>()));
    pending.complete(http.Response('{}', 200));
    expect(budgets.length, 2);
    expect(budgets.last, lessThan(budgets.first));
    expect(direct, 0);
  });

  test(
    'session refresh and direct fallback share the request deadline',
    () async {
      var sent = 0;
      var direct = 0;
      final hungRefresh = Completer<String?>();
      final request = GatewayRequest(
        bases: ['https://first.test', 'https://second.test'],
        totalTimeout: const Duration(milliseconds: 30),
        send: (_, __, ___) async {
          sent++;
          return http.Response('{}', 401);
        },
        refresh: () => hungRefresh.future,
        direct: () async {
          direct++;
          return {};
        },
      ).run('source-match-list', 'test-token');
      await expectLater(request, throwsA(isA<TimeoutException>()));
      hungRefresh.complete('late-token');
      expect(sent, 1);
      expect(direct, 0);

      final pendingDirect = Completer<dynamic>();
      final directRequest = GatewayRequest(
        bases: [],
        totalTimeout: const Duration(milliseconds: 30),
        send: (_, __, ___) async => throw StateError('No gateway route'),
        refresh: () async => null,
        direct: () => pendingDirect.future,
      ).run('source-match-list', 'test-token');
      await expectLater(directRequest, throwsA(isA<Exception>()));
      pendingDirect.complete({});
    },
  );

  test(
    'a 401 refresh retries the same route with the new token only once',
    () async {
      final tokens = <String>[];
      final routes = <String>[];
      var refreshes = 0;
      final result = await GatewayRequest(
        bases: ['https://first.test', 'https://second.test'],
        send: (uri, token, _) async {
          tokens.add(token);
          routes.add(uri.host);
          return token == 'expired'
              ? http.Response('{}', 401)
              : http.Response('{"ok":true}', 200);
        },
        refresh: () async {
          refreshes++;
          return 'fresh';
        },
        direct: () async => throw StateError('Direct must not be used'),
      ).run('system-monitor', 'expired', body: {'action': 'connect'});
      expect(result.data, {'ok': true});
      expect(tokens, ['expired', 'fresh']);
      expect(routes, ['first.test', 'first.test']);
      expect(refreshes, 1);
    },
  );

  test(
    'a global-budget timeout stops even if the stopwatch has a remainder',
    () async {
      var sent = 0;
      var direct = 0;
      final hungRefresh = Completer<String?>();
      final request = runZoned(
        () => GatewayRequest(
          bases: ['https://first.test', 'https://second.test'],
          totalTimeout: const Duration(seconds: 1),
          send: (_, __, ___) async {
            sent++;
            return http.Response('{}', 401);
          },
          refresh: () => hungRefresh.future,
          direct: () async {
            direct++;
            return {};
          },
        ).run('source-match-list', 'test-token'),
        // Model a deadline timer firing before the monotonic clock reaches the
        // exact boundary. Successful futures still complete as microtasks.
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) =>
              parent.createTimer(zone, Duration.zero, callback),
        ),
      );
      await expectLater(request, throwsA(isA<TimeoutException>()));
      hungRefresh.complete('late-token');
      expect(sent, 1);
      expect(direct, 0);
    },
  );
}
