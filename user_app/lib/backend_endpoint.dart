import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

const vpnFreeSupabaseRelays = <String>[
  'https://supabase-api.nyeinchanaung.ccwu.cc',
  'https://supabase-api.nyeinchanaung.us.ci',
  vercelBackupBase,
];

String? _selectedBackend;
String? get selectedBackend => _selectedBackend;
bool get usesVercelBackend => _selectedBackend == vercelBackupBase;

Future<String> resolveSupabaseUrl({
  required String directUrl,
  required String publishableKey,
}) async {
  final normalizedDirect = directUrl.replaceAll(RegExp(r'/+$'), '');
  final candidates = <({String base, Uri health, bool direct})>[
    for (final relay in vpnFreeSupabaseRelays)
      (
        base: relay,
        health: Uri.parse(
          relay == vercelBackupBase ? '$relay/backend-health' : '$relay/health',
        ),
        direct: false,
      ),
    (
      base: normalizedDirect,
      health: Uri.parse('$normalizedDirect/auth/v1/health'),
      direct: true,
    ),
  ];

  final completer = Completer<String>();
  var remaining = candidates.length;

  final clients = <http.Client>[];
  for (final candidate in candidates) {
    final client = http.Client();
    clients.add(client);
    () async {
      try {
        final response = await client
            .get(
              candidate.health,
              headers: {
                'Accept': 'application/json',
                if (candidate.direct) 'apikey': publishableKey,
              },
            )
            .timeout(
              Duration(seconds: candidate.base == vercelBackupBase ? 5 : 3),
            );

        final decoded = jsonDecode(response.body);
        final healthy =
            candidate.direct ||
            (decoded is Map &&
                decoded['ok'] == true &&
                decoded['service'] == 'supabase-relay');
        if (!completer.isCompleted &&
            healthy &&
            response.statusCode >= 200 &&
            response.statusCode < 300) {
          _selectedBackend = candidate.base;
          completer.complete(candidate.base);
        }
      } catch (_) {
        // Another relay/direct candidate may still work.
      } finally {
        client.close();
        remaining -= 1;
        if (remaining == 0 && !completer.isCompleted) {
          _selectedBackend = normalizedDirect;
          completer.complete(normalizedDirect);
        }
      }
    }();
  }

  try {
    return await completer.future;
  } finally {
    for (final client in clients) {
      client.close();
    }
  }
}
