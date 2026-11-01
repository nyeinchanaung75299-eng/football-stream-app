import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

// Admin authentication must use a verified Supabase Auth endpoint. A generic
// public /health response is not proof that a relay can serve GoTrue sign-in.
const vpnFreeSupabaseRelays = <String>[
  vercelBackupBase,
  'https://supabase-api.nyeinchanaung.ccwu.cc',
  'https://supabase-api.nyeinchanaung.us.ci',
];

String? _selectedBackend;
String? get selectedBackend => _selectedBackend;
bool get usesVercelBackend => _selectedBackend == vercelBackupBase;

// Network probes run concurrently instead of waiting for up to 15 seconds of
// sequential timeouts. Only known endpoints and an actual GoTrue health
// response can be selected. Auth, role checks and RLS still run normally.
Future<String> resolveSupabaseUrl({
  required String directUrl,
  required String publishableKey,
  String? preferredBase,
}) async {
  final direct = directUrl.replaceAll(RegExp(r'/+$'), '');
  final candidates = <({String base, Uri health, Duration timeout})>[
    (
      base: vercelBackupBase,
      health: Uri.parse('$vercelBackupBase/backend-health'),
      timeout: const Duration(seconds: 4),
    ),
    for (final relay in vpnFreeSupabaseRelays.skip(1))
      (
        base: relay,
        health: Uri.parse('$relay/auth/v1/health'),
        timeout: const Duration(seconds: 3),
      ),
    (
      base: direct,
      health: Uri.parse('$direct/auth/v1/health'),
      timeout: const Duration(seconds: 3),
    ),
  ];

  final unique = <String, ({String base, Uri health, Duration timeout})>{
    for (final candidate in candidates) candidate.base: candidate,
  }.values.toList(growable: false);

  // A previously working Auth route gets a small head start, but only after
  // another real health check. A stale route never blocks all alternatives.
  final preferred = unique.any((candidate) => candidate.base == preferredBase)
      ? preferredBase
      : null;
  final result = Completer<String>();
  var unfinished = unique.length;

  Future<void> probe(({String base, Uri health, Duration timeout}) candidate) async {
    if (result.isCompleted) return;
    final client = http.Client();
    try {
      final reply = await client.get(candidate.health, headers: {
        'Accept': 'application/json',
        'apikey': publishableKey,
      }).timeout(candidate.timeout);
      if (reply.statusCode < 200 || reply.statusCode >= 300) return;
      final body = jsonDecode(reply.body);
      if (body is! Map || body['name'] != 'GoTrue') return;
      if (!result.isCompleted) {
        _selectedBackend = candidate.base;
        result.complete(candidate.base);
      }
    } catch (_) {
      // One unreachable endpoint should not delay any other route.
    } finally {
      client.close();
      unfinished--;
      if (unfinished == 0 && !result.isCompleted) {
        // Keep the existing retryable direct-Auth fallback. Authorization
        // never proceeds unless Supabase Auth itself is initialized.
        _selectedBackend = direct;
        result.complete(direct);
      }
    }
  }

  for (final candidate in unique) {
    if (preferred != null && candidate.base != preferred) {
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 150),
        () => probe(candidate),
      ));
    } else {
      unawaited(probe(candidate));
    }
  }
  return result.future;
}
