import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/admin_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  SupabaseAdminAuthService serviceFor(
    MockClient transport, {
    Duration timeout = const Duration(seconds: 1),
  }) {
    final client = SupabaseClient(
      'https://example.invalid',
      'public-test-key',
      httpClient: transport,
    );
    addTearDown(client.dispose);
    return SupabaseAdminAuthService(
      client: client,
      roleLookupTimeout: timeout,
    );
  }

  test('admin access comes from the authenticated user profile role', () async {
    final service = serviceFor(MockClient((request) async {
      expect(request.url.path, '/rest/v1/profiles');
      expect(request.url.queryParameters['select'], 'role');
      expect(request.url.queryParameters['id'], 'eq.admin-user');
      return http.Response(jsonEncode([{'role': 'admin'}]), 200);
    }));

    expect(await service.isAdmin('admin-user'), isTrue);
  });

  test('a non-admin profile does not authorize access', () async {
    final service = serviceFor(MockClient((_) async {
      return http.Response(jsonEncode([{'role': 'viewer'}]), 200);
    }));

    expect(await service.isAdmin('viewer'), isFalse);
  });

  test('a missing profile does not authorize access', () async {
    final service = serviceFor(MockClient((_) async {
      return http.Response('[]', 200);
    }));

    expect(await service.isAdmin('missing-user'), isFalse);
  });

  test('a profile transport that never answers times out', () async {
    final service = serviceFor(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      service.isAdmin('admin-user'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
