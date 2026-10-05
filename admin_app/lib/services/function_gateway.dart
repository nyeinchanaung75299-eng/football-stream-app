import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';

class FunctionGateway {
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue:
        'https://football-api.nyeinchanaung.us.ci',
  );

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

    final base = _publicApiBase.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/admin/functions/${Uri.encodeComponent(functionName)}',
    );

    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Cache-Control': 'no-store',
            },
            body: jsonEncode(body ?? const <String, dynamic>{}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Keep a direct Supabase fallback only for an edge/network failure.
      await AnalyticsService.capture(
        'admin function fallback used',
        properties: {
          'function': functionName,
          'reason': 'gateway_network_error',
        },
      );
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
            'reason': 'gateway_and_direct_failed',
          },
        );
        rethrow;
      }
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
          'transport': 'cloudflare_gateway',
          'status_code': response.statusCode,
        },
      );
      return decoded;
    }

    // A newly added admin Edge Function can briefly be newer than the
    // Cloudflare allow-list. Fall back to Supabase directly for gateway
    // routing/upstream failures instead of breaking the Admin workflow.
    if (response.statusCode == 404 ||
        response.statusCode == 502 ||
        response.statusCode == 503) {
      await AnalyticsService.capture(
        'admin function fallback used',
        properties: {
          'function': functionName,
          'reason': 'gateway_http_${response.statusCode}',
        },
      );
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
            'reason': 'gateway_and_direct_failed',
          },
        );
        rethrow;
      }
    }

    final detail = decoded is Map && decoded['error'] != null
        ? decoded['error'].toString()
        : 'HTTP ${response.statusCode}';
    await AnalyticsService.capture(
      'admin function failed',
      properties: {
        'function': functionName,
        'reason': 'gateway_http_error',
        'status_code': response.statusCode,
      },
    );
    throw Exception('Gateway error: $detail');
  }
}
