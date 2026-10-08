import 'dart:async';

import 'package:http/http.dart' as http;

const vpnFreeSupabaseRelays = <String>[
  'https://supabase-api.nyeinchanaung.ccwu.cc',
  'https://supabase-api.nyeinchanaung.us.ci',
];

Future<String> resolveSupabaseUrl({
  required String directUrl,
  required String publishableKey,
}) async {
  final normalizedDirect = directUrl.replaceAll(RegExp(r'/+$'), '');
  final candidates = <({String base, Uri health, bool direct})>[
    for (final relay in vpnFreeSupabaseRelays)
      (
        base: relay,
        health: Uri.parse('$relay/health'),
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

  for (final candidate in candidates) {
    () async {
      try {
        final response = await http
            .get(
              candidate.health,
              headers: {
                'Accept': 'application/json',
                if (candidate.direct) 'apikey': publishableKey,
              },
            )
            .timeout(const Duration(seconds: 3));

        if (!completer.isCompleted &&
            response.statusCode >= 200 &&
            response.statusCode < 300) {
          completer.complete(candidate.base);
        }
      } catch (_) {
        // Another relay/direct candidate may still work.
      } finally {
        remaining -= 1;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(normalizedDirect);
        }
      }
    }();
  }

  return completer.future;
}
