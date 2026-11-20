import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/source_route_policy.dart';
import 'package:football_viewer/network_endpoints.dart';

void main() {
  test(
    'reachable Cloudflare extraction never invokes Vercel; empty results are authoritative',
    () async {
      var probes = 0;
      final calls = <String>[];
      final policy = SourceRoutePolicy(
        knownPrimary: () => null,
        clientFactory: () => MockClient((r) async {
          probes++;
          return http.Response('{"ok":true}', 200);
        }),
      );
      final rows = await policy.read((base) async {
        calls.add(base);
        return <String>[];
      });
      expect(rows, isEmpty);
      expect(calls, [cloudflarePublicBase]);
      expect(probes, 1);
      await policy.preferred();
      expect(probes, 1);
    },
  );
  test(
    'blocked Cloudflare uses one shared cheap probe, never duplicate extraction',
    () async {
      var probes = 0;
      final gate = Completer<http.Response>();
      final calls = <String>[];
      final policy = SourceRoutePolicy(
        knownPrimary: () => null,
        clientFactory: () => MockClient((r) {
          probes++;
          return gate.future;
        }),
      );
      final first = policy.read((base) async {
        calls.add(base);
        return 'one';
      });
      final second = policy.read((base) async {
        calls.add(base);
        return 'two';
      });
      gate.complete(http.Response('blocked', 403));
      expect(await first, 'one');
      expect(await second, 'two');
      expect(probes, 1);
      expect(calls, [vercelBackupBase, vercelBackupBase]);
    },
  );
  test(
    'recent verified Cloudflare skips health request and failed reads fall back once',
    () async {
      var probes = 0;
      final calls = <String>[];
      final policy = SourceRoutePolicy(
        knownPrimary: () => cloudflarePublicBase,
        clientFactory: () => MockClient((_) async {
          probes++;
          return http.Response('', 500);
        }),
      );
      expect(
        await policy.read((base) async {
          calls.add(base);
          if (base != vercelBackupBase) throw StateError('network');
          return 7;
        }),
        7,
      );
      expect(calls, [cloudflarePublicBase, vercelBackupBase]);
      expect(probes, 0);
      expect(await policy.preferred(), vercelBackupBase);
    },
  );
  test(
    'expired fallback retries primary and arbitrary remembered hosts cannot be selected',
    () async {
      var now = DateTime.utc(2026, 11, 20);
      var probes = 0;
      final policy = SourceRoutePolicy(
        knownPrimary: () => 'https://foreign.example',
        now: () => now,
        clientFactory: () => MockClient((_) async {
          probes++;
          return http.Response(
            probes == 1 ? 'blocked' : '{"ok":true}',
            probes == 1 ? 403 : 200,
          );
        }),
      );
      expect(await policy.preferred(), vercelBackupBase);
      now = now.add(const Duration(minutes: 2));
      expect(await policy.preferred(), cloudflarePublicBase);
      expect(probes, 2);
    },
  );
}
