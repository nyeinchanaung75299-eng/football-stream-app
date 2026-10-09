import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../backend_endpoint.dart';
import '../network_endpoints.dart';

class FunctionGateway {
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );

  static List<String> get _gatewayBases =>
      publicApiBases(primary: _publicApiBase, preferVercel: usesVercelBackend);

  static Future<dynamic> invoke(
    String functionName, {
    Object? body,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    await AnalyticsService.capture(
      'admin function invoked',
      properties: {'function': functionName},
    );

    if (token == null || token.isEmpty) {
      await AnalyticsService.capture(
        'admin function failed',
        properties: {
          'function': functionName,
          'reason': 'no_admin_session',
        },
      );
      throw StateError('Admin session is not available.');
    }

    dynamic lastDecoded;
    int? lastStatus;
    var accessToken = token;
    var refreshedSession = false;

    for (var index = 0; index < _gatewayBases.length; index += 1) {
      final base = _gatewayBases[index];
      final uri = Uri.parse(
        '$base/admin/functions/${Uri.encodeComponent(functionName)}',
      );

      Future<http.Response> send(String bearer) {
        return http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer $bearer',
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Cache-Control': 'no-store',
              },
              body: jsonEncode(body ?? const <String, dynamic>{}),
            )
            .timeout(
                Duration(seconds: functionName == 'system-monitor' ? 20 : 9));
      }

      http.Response response;
      try {
        response = await send(accessToken);

        // Source tools were occasionally returning 401 with an expired access
        // token even though the Admin still had a valid refresh session.
        if (response.statusCode == 401 && !refreshedSession) {
          refreshedSession = true;
          final refreshed =
              await Supabase.instance.client.auth.refreshSession();
          final nextToken = refreshed.session?.accessToken;
          if (nextToken != null && nextToken.isNotEmpty) {
            accessToken = nextToken;
            response = await send(accessToken);
          }
        }
      } catch (_) {
        await AnalyticsService.capture(
          'admin function fallback used',
          properties: {
            'function': functionName,
            'reason': 'gateway_${index + 1}_network_error',
          },
        );
        continue;
      }

      dynamic decoded;
      if (response.body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = response.body;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await AnalyticsService.capture(
          'admin function completed',
          properties: {
            'function': functionName,
            'transport': base == vercelBackupBase
                ? 'vercel_backup'
                : (Uri.parse(base).host.endsWith('.workers.dev')
                    ? 'cloudflare_workers_dev'
                    : 'cloudflare_custom_domain'),
            'status_code': response.statusCode,
          },
        );
        return decoded;
      }

      lastDecoded = decoded;
      lastStatus = response.statusCode;

      if (response.statusCode == 404 ||
          response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504) {
        await AnalyticsService.capture(
          'admin function fallback used',
          properties: {
            'function': functionName,
            'reason': 'gateway_http_${response.statusCode}',
          },
        );
        continue;
      }

      final detail = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'HTTP ${response.statusCode}';
      throw Exception('Gateway error: $detail');
    }

    try {
      final direct = await Supabase.instance.client.functions.invoke(
        functionName,
        body: body,
      );
      await AnalyticsService.capture(
        'admin function completed',
        properties: {
          'function': functionName,
          'transport': 'supabase_direct',
        },
      );
      return direct.data;
    } catch (_) {
      await AnalyticsService.capture(
        'admin function failed',
        properties: {
          'function': functionName,
          'reason': 'all_transports_failed',
        },
      );

      final detail = lastDecoded is Map && lastDecoded['error'] != null
          ? lastDecoded['error'].toString()
          : lastStatus == null
              ? 'Admin backend is unreachable on this network.'
              : 'HTTP $lastStatus';
      throw Exception(detail);
    }
  }
}
