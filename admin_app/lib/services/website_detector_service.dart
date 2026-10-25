import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network_endpoints.dart';

class WebsiteScanResult {
  const WebsiteScanResult({
    required this.links,
    required this.notes,
    required this.mode,
    this.partial = false,
    this.diagnostics = const {},
  });

  final List<Map<String, String>> links;
  final String notes;
  final String mode;
  final bool partial;
  final Map<String, Object?> diagnostics;
}

/// Server-side HTML scan for public, authorized pages. Requests go only to
/// the NCA authenticated Worker, never to arbitrary user URLs from the web UI.
class WebsiteDetectorService {
  const WebsiteDetectorService();

  Future<WebsiteScanResult> scan(String websiteUrl, {bool browser = false}) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Please sign in to Admin before scanning.');
    }

    final client = http.Client();
    try {
      // The alternate Vercel host is often more reachable than the Worker
      // domains on some mobile networks. Its route forwards to the *same*
      // authenticated Cloudflare scanner and does not bypass its role checks.
      // Browser Run spends scarce Free browser minutes. Never fan out a
      // long-running scan across several gateways: the other gateways would
      // start duplicate Cloudflare browser sessions for the same page.
      // Use the direct Worker first, Vercel only if connection fails quickly.
      final bases = browser
          ? <String>[
              'https://football-public-api.nyeinchanaung75299-eng.workers.dev',
              vercelBackupBase,
            ]
          : publicApiBases(
              primary: 'https://football-api.nyeinchanaung.us.ci',
              preferVercel: true,
            );
      final clock = Stopwatch()..start();
      String lastFailure = 'No scanner gateway responded.';
      for (final base in bases) {
        if (browser && clock.elapsed >= const Duration(seconds: 5)) break;
        try {
          final response = await client.post(
            Uri.parse(base + (browser
                ? '/admin/stream-detect-browser'
                : '/admin/stream-detect')),
            headers: {
              'Authorization': 'Bearer ' + token,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'url': websiteUrl.trim(),
              'authorized': true,
            }),
          ).timeout(Duration(seconds: browser ? 23 : 25));
          dynamic payload;
          try {
            payload = jsonDecode(response.body);
          } catch (_) {
            if (response.statusCode == 404 || response.statusCode >= 500) {
              lastFailure = 'Gateway returned HTTP ${response.statusCode}.';
              continue;
            }
            throw const FormatException('Invalid website scanner response.');
          }
          if (response.statusCode == 404) {
            lastFailure = 'Scanner route not found on ${Uri.parse(base).host}.';
            continue;
          }
          if (browser && payload is Map &&
              (payload['code'] == 'browser_disabled' ||
               payload['code'] == 'browser_unavailable')) {
            throw StateError(payload['error']?.toString() ??
                'Cloudflare Browser Run Free mode is unavailable.');
          }
          if (response.statusCode >= 500) {
            final message = payload is Map ? payload['error']?.toString() : null;
            lastFailure = message != null && message.isNotEmpty
                ? 'Scanner backend: $message'
                : 'Gateway returned HTTP ${response.statusCode}.';
            if (browser) {
              // Do not accidentally launch the same Browser Run session via
              // another gateway after a backend error.
              throw StateError(lastFailure);
            }
            continue;
          }
          if (response.statusCode >= 400) {
            final error = payload is Map ? payload['error'] : null;
            throw StateError(
              error?.toString() ??
                  'Website scan returned HTTP ' + response.statusCode.toString(),
            );
          }
          if (payload is! Map || payload['ok'] != true ||
              payload['links'] is! List) {
            throw const FormatException('Invalid website scanner results.');
          }
          final rows = (payload['links'] as List)
              .whereType<Map>()
              .map((row) => <String, String>{
                    'url': (row['url'] ?? '').toString(),
                    'type': (row['type'] ?? '').toString(),
                    'referer': (row['referer'] ?? '').toString(),
                    'origin': (row['origin'] ?? '').toString(),
                  })
              .where((row) {
                final uri = Uri.tryParse(row['url']!);
                return uri != null &&
                    const {'http', 'https'}.contains(uri.scheme) &&
                    uri.host.isNotEmpty &&
                    const {'hls', 'dash', 'mp4', 'flv'}.contains(row['type']);
              })
              .take(35)
              .toList(growable: false);
          return WebsiteScanResult(
            links: rows,
            notes: (payload['notes'] ?? '').toString(),
            mode: (payload['mode'] ?? 'html-scan').toString(),
            partial: payload['partial'] == true,
            diagnostics: payload['diagnostics'] is Map
                ? (payload['diagnostics'] as Map).map(
                    (k, v) => MapEntry(
                      k.toString(),
                      (v is int || v is bool) ? v : null,
                    ),
                  )
                : const {},
          );
        } on StateError {
          rethrow;
        } on TimeoutException {
          lastFailure = browser
              ? 'Browser scan timed out. Try again once or use HTML mode.'
              : 'Gateway timed out while scanning the website.';
          if (browser) break;
        } on http.ClientException {
          lastFailure = 'Could not reach ${Uri.parse(base).host} from this network.';
        } catch (_) {
          lastFailure = 'Gateway response could not be read.';
        }
      }
      throw StateError(
        browser
          ? 'Browser network detection did not finish. $lastFailure'
          : 'Website scanner connection failed. $lastFailure '
              'Try another connection if this continues.',
      );
    } finally {
      client.close();
    }
  }
}
