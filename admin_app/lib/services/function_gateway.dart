import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../network_endpoints.dart';
import 'gateway_request.dart';

class FunctionGateway {
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );
  // Public/Admin proxy calls prefer the reachable Vercel route regardless
  // of which separate Supabase Auth relay was chosen.
  static List<String> get _gatewayBases =>
      publicApiBases(primary: _publicApiBase, preferVercel: true);

  static Future<dynamic> invoke(String functionName, {Object? body}) async {
    final client = Supabase.instance.client;
    final token = client.auth.currentSession?.accessToken;
    final elapsed = Stopwatch()..start();
    unawaited(AnalyticsService.capture('admin function invoked',
        properties: {'function': functionName}));
    if (token == null || token.isEmpty) {
      unawaited(AnalyticsService.capture('admin function failed', properties: {
        'function': functionName,
        'reason': 'no_admin_session',
      }));
      throw StateError('Admin session is not available.');
    }

    try {
      final result = await GatewayRequest(
        bases: _gatewayBases,
        send: (uri, bearer, timeout) async {
          final transport = http.Client();
          try {
            return await transport
                .post(uri,
                    headers: {
                      'Authorization': 'Bearer $bearer',
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                      'Cache-Control': 'no-store',
                    },
                    body: jsonEncode(body ?? const <String, dynamic>{}))
                .timeout(timeout);
          } finally {
            transport.close();
          }
        },
        refresh: () async =>
            (await client.auth.refreshSession()).session?.accessToken,
        direct: () async =>
            (await client.functions.invoke(functionName, body: body)).data,
        onFallback: (reason) => unawaited(AnalyticsService.capture(
            'admin function fallback used',
            properties: {'function': functionName, 'reason': reason})),
      ).run(functionName, token, body: body);

      unawaited(
          AnalyticsService.capture('admin function completed', properties: {
        'function': functionName,
        'duration_ms': elapsed.elapsedMilliseconds,
        'transport': result.base == null
            ? 'supabase_direct'
            : result.base == vercelBackupBase
                ? 'vercel_backup'
                : (Uri.parse(result.base!).host.endsWith('.workers.dev')
                    ? 'cloudflare_workers_dev'
                    : 'cloudflare_custom_domain'),
        if (result.statusCode != null) 'status_code': result.statusCode!,
      }));
      return result.data;
    } catch (_) {
      unawaited(AnalyticsService.capture('admin function failed', properties: {
        'function': functionName,
        'reason': 'request_failed',
        'duration_ms': elapsed.elapsedMilliseconds,
      }));
      rethrow;
    }
  }
}
