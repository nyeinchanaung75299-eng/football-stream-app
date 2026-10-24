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
      final bases = publicApiBases(
        primary: 'https://football-api.nyeinchanaung.us.ci',
      );
      final preferred = <String>[
        ...bases.where((base) => !base.contains('vercel.app')),
        ...bases.where((base) => base.contains('vercel.app')),
      ];
      for (final base in preferred) {
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
          ).timeout(const Duration(seconds: 13));
          dynamic payload;
          try {
            payload = jsonDecode(response.body);
          } catch (_) {
            if (response.statusCode == 404 || response.statusCode >= 500) {
              continue;
            }
            throw const FormatException('Invalid website scanner response.');
          }
          if (response.statusCode == 404 || response.statusCode >= 500) {
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
        } catch (_) {
          // A blocked API route may be reachable using another NCA gateway.
        }
      }
      throw StateError(
        'Cannot connect to the website scanner. '
        'Check Cloudflare Worker deployment and try again.',
      );
    } finally {
      client.close();
    }
  }
}
