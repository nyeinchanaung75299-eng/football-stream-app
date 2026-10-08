import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/backend_endpoint.dart';
import 'package:football_viewer/network_endpoints.dart';

void main() {
  test(
    'a fast rejected health response cannot beat a healthy backend',
    () async {
      await http.runWithClient(
        () async {
          final result = await resolveSupabaseUrl(
            directUrl: 'https://database.example',
            publishableKey: 'test-public-key',
          );
          expect(result, 'https://database.example');
        },
        () => MockClient((request) async {
          if (request.url.host == 'database.example') {
            await Future<void>.delayed(Duration.zero);
            return http.Response('{}', 200);
          }
          return http.Response('{}', 401);
        }),
      );
    },
  );

  test(
    'Vercel backend health enables Auth/REST when the other routes are blocked',
    () async {
      await http.runWithClient(
        () async {
          final result = await resolveSupabaseUrl(
            directUrl: 'https://database.example/',
            publishableKey: 'test-public-key',
          );
          expect(result, vercelBackupBase);
          expect(usesVercelBackend, isTrue);
          expect(
            publicApiBases(preferVercel: usesVercelBackend).first,
            vercelBackupBase,
          );
        },
        () => MockClient((request) async {
          if (request.url.host == Uri.parse(vercelBackupBase).host) {
            expect(request.url.path, '/backend-health');
            return http.Response('{"ok":true,"service":"supabase-relay"}', 200);
          }
          throw http.ClientException('Blocked fixture route');
        }),
      );
    },
  );

  test(
    'A reachable public health response cannot select an unhealthy Auth relay',
    () async {
      await http.runWithClient(
        () async {
          final result = await resolveSupabaseUrl(
            directUrl: 'https://database.example/',
            publishableKey: 'test-public-key',
          );
          expect(result, 'https://database.example');
          expect(usesVercelBackend, isFalse);
        },
        () => MockClient((request) async {
          if (request.url.host == 'database.example') {
            await Future<void>.delayed(Duration.zero);
            return http.Response('{}', 200);
          }
          return http.Response(
            '{"ok":true,"service":"football-public-api"}',
            200,
          );
        }),
      );
    },
  );

  test(
    'All failed routes finish with the original endpoint; API lists never duplicate the backup',
    () async {
      await http.runWithClient(() async {
        final result = await resolveSupabaseUrl(
          directUrl: 'https://database.example/',
          publishableKey: 'test-public-key',
        );
        expect(result, 'https://database.example');
      }, () => MockClient((_) async => http.Response('{}', 503)));
      final routes = publicApiBases(primary: '$vercelBackupBase/');
      expect(routes.where((base) => base == vercelBackupBase).length, 1);
    },
  );
}
