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
  });

  final List<Map<String, String>> links;
  final String notes;
  final String mode;
}

/// Server-side HTML scan for public, authorized pages. Requests go only to
/// the NCA authenticated Worker, never to arbitrary user URLs from the web UI.
class WebsiteDetectorService {
  const WebsiteDetectorService();

  Future<WebsiteScanResult> scan(String websiteUrl) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Please sign in to Admin before scanning.');
    }

    final client = http.Client();
    try {
      // The alternate Vercel host is often more reachable than the Worker
      // domains on some mobile networks. Its route forwards to the *same*
      // authenticated Cloudflare scanner and does not bypass its role checks.
      final bases = publicApiBases(
        primary: 'https://football-api.nyeinchanaung.us.ci',
        preferVercel: true,
      );
      String lastFailure = 'No scanner gateway responded.';
      for (final base in bases) {
        try {
          final response = await client.post(
            Uri.parse(base + '/admin/stream-detect'),
            headers: {
              'Authorization': 'Bearer ' + token,
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'url': websiteUrl.trim(),
              'authorized': true,
            }),
          ).timeout(const Duration(seconds: 25));
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
          if (response.statusCode >= 500) {
            final message = payload is Map ? payload['error']?.toString() : null;
            lastFailure = message != null && message.isNotEmpty
                ? 'Scanner backend: $message'
                : 'Gateway returned HTTP ${response.statusCode}.';
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
          );
        } on StateError {
          rethrow;
        } on TimeoutException {
          lastFailure = 'Gateway timed out while scanning the website.';
        } on http.ClientException {
          lastFailure = 'Could not reach ${Uri.parse(base).host} from this network.';
        } catch (_) {
          lastFailure = 'Gateway response could not be read.';
        }
      }
      throw StateError(
        'Website scanner connection failed. $lastFailure '
        'Try another connection if this continues.',
      );
    } finally {
      client.close();
    }
  }
}
