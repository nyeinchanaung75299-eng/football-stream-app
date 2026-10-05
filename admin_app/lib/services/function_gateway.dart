import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class FunctionGateway {
  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue:
        'https://football-public-api.nyeinchanaung75299-eng.workers.dev',
  );

  static Future<dynamic> invoke(
    String functionName, {
    Object? body,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken;

    if (token == null || token.isEmpty) {
      throw StateError('Admin session is not available.');
    }

    final base = _publicApiBase.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$base/admin/functions/${Uri.encodeComponent(functionName)}',
    );

    try {
      final response = await http
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

      dynamic decoded;
      if (response.body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          decoded = response.body;
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      final detail = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'HTTP ${response.statusCode}';
      throw Exception('Gateway error: $detail');
    } catch (_) {
      // Keep a direct Supabase fallback for networks where the project
      // hostname is reachable and the edge gateway is temporarily unavailable.
      final direct = await Supabase.instance.client.functions.invoke(
        functionName,
        body: body,
      );
      return direct.data;
    }
  }
}
