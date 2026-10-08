import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/backend_endpoint.dart';

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
}
