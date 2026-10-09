import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../backend_endpoint.dart';
import '../network_endpoints.dart';
import 'gateway_request.dart';

class FunctionGateway {
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );
  static String? _healthyBase;

  static List<String> get _gatewayBases {
    final bases = publicApiBases(
        primary: _publicApiBase, preferVercel: usesVercelBackend);
    final healthy = _healthyBase;
    if (healthy != null && bases.remove(healthy)) bases.insert(0, healthy);
    return bases;
  }

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

      if (result.base != null) _healthyBase = result.base;
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
