import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

class PublicHighlightsService {
  const PublicHighlightsService({this.client});
  final http.Client? client;
  Future<Map<String, dynamic>> request(
    String action, {
    int offset = 0,
    String query = '',
    String? entryId,
    bool force = false,
  }) async {
    final transport = client ?? http.Client();
    try {
      for (final base in [
        '$cloudflarePublicBase/highlights',
        independentPublicBase.replaceFirst(
          'viewer-network-api',
          'public-highlights',
        ),
      ]) {
        try {
          final uri = Uri.parse(base).replace(
            queryParameters: {
              'action': action,
              'offset': '$offset',
              if (query.isNotEmpty) 'query': query,
              if (entryId != null) 'entry_id': entryId,
              if (force) 'refresh': '1',
            },
          );
          final response = await transport
              .get(uri, headers: const {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          if (data is Map &&
              data['ok'] == true &&
              data['source'] == 'highlights' &&
              data['provider'] == 'dasfootball')
            return Map<String, dynamic>.from(data);
        } catch (_) {
          /* Try the independent public route, without Admin auth. */
        }
      }
      throw StateError('Highlights unavailable. Pull to refresh or retry.');
    } finally {
      if (client == null) transport.close();
    }
  }
}
