import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../network_endpoints.dart';
import 'gateway_request.dart';

/// Only reorder known configured gateway hosts; never accept a URL supplied
/// by a response or user input. Auth and role checks are unchanged.
List<String> prioritizeKnownGateway(List<String> known, String? preferred) {
  if (preferred == null || !known.contains(preferred)) {
    return List<String>.of(known);
  }
  return [preferred, ...known.where((base) => base != preferred)];
}

class FunctionGateway {
  static String? _lastHealthyReadBase;
  static DateTime? _lastHealthyReadAt;
  static const _rememberFor = Duration(minutes: 5);
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );
  // Public/Admin proxy calls prefer the reachable Vercel route regardless
  // of which separate Supabase Auth relay was chosen.
  static List<String> get _gatewayBases =>
      publicApiBases(primary: _publicApiBase, preferVercel: true);

  static List<String> _basesFor(String functionName, Object? body) {
    final known = _gatewayBases;
    // Only read-only functions are replayed and route-optimized. An uncertain
    // write must continue on its original single-first route.
    if (!GatewayRequest.canRetry(functionName, body)) return known;
    final when = _lastHealthyReadAt;
    final fresh = when != null &&
        DateTime.now().difference(when) < _rememberFor;
    return prioritizeKnownGateway(known, fresh ? _lastHealthyReadBase : null);
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
        bases: _basesFor(functionName, body),
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

      if (result.base != null && GatewayRequest.canRetry(functionName, body)) {
        _lastHealthyReadBase = result.base;
        _lastHealthyReadAt = DateTime.now();
      }
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
