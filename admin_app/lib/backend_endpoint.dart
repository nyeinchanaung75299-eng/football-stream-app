import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

// Admin authentication must use a verified Supabase Auth endpoint. A fast
// generic Cloudflare health response does NOT prove that sign-in / profiles
// are reachable on mobile networks without a VPN.
const vpnFreeSupabaseRelays = <String>[
  vercelBackupBase,
  'https://supabase-api.nyeinchanaung.ccwu.cc',
  'https://supabase-api.nyeinchanaung.us.ci',
];

String? _selectedBackend;
String? get selectedBackend => _selectedBackend;
bool get usesVercelBackend => _selectedBackend == vercelBackupBase;

Future<String> resolveSupabaseUrl({
  required String directUrl,
  required String publishableKey,
}) async {
  final normalizedDirect = directUrl.replaceAll(RegExp(r'/+$'), '');
  final candidates = <({String base, Uri health, bool vercel, bool direct})>[
    for (final relay in vpnFreeSupabaseRelays)
      (
        base: relay,
        health: Uri.parse(
          relay == vercelBackupBase
              ? '$relay/backend-health'
              : '$relay/health',
        ),
        vercel: relay == vercelBackupBase,
        direct: false,
      ),
    (
      base: normalizedDirect,
      health: Uri.parse('$normalizedDirect/auth/v1/health'),
      vercel: false,
      direct: true,
    ),
  ];

  // Do not race the direct Supabase endpoint against Vercel: the direct
  // endpoint may pass a server probe yet be inaccessible from the user's
  // VPN-off phone. Prefer one proven working VPN-free route first.
  for (final candidate in candidates) {
    final client = http.Client();
    try {
      final response = await client.get(candidate.health, headers: {
        'Accept': 'application/json',
        if (candidate.vercel || candidate.direct) 'apikey': publishableKey,
      }).timeout(Duration(seconds: candidate.vercel ? 6 : 3));
      if (response.statusCode < 200 || response.statusCode >= 300) continue;
      final decoded = jsonDecode(response.body);
      final healthy = candidate.vercel
          ? (decoded is Map && decoded['name'] == 'GoTrue')
          : candidate.direct
              ? decoded is Map
              : (decoded is Map &&
                  decoded['ok'] == true &&
                  decoded['service'] == 'supabase-relay');
      if (healthy) {
        _selectedBackend = candidate.base;
        return candidate.base;
      }
    } catch (_) {
      // Try the next candidate. No bypass of Admin role authorization.
    } finally {
      client.close();
    }
  }
  // Preserve a retryable initialization path on unusually restricted
  // networks; no authentication is performed without Supabase Auth.
  _selectedBackend = normalizedDirect;
  return normalizedDirect;
}
