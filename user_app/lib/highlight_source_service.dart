import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

class PublicHighlightsService {
  const PublicHighlightsService({this.client});

  final http.Client? client;
  static const pageSize = 25;

  Future<List<Map<String, dynamic>>> list(int offset) async {
    final transport = client ?? http.Client();
    try {
      for (final base in [
        vercelBackupBase,
        Uri.parse(independentPublicBase).origin,
      ]) {
        try {
          final uri = Uri.parse(
            '$base/rest/v1/rpc/viewer_highlight_matches',
          ).replace(queryParameters: {'p_offset': '$offset'});
          final response = await transport
              .get(
                uri,
                headers: const {
                  'Accept': 'application/json',
                  'apikey': viewerPublicApiKey,
                },
              )
              .timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) continue;
          final data = jsonDecode(response.body);
          if (data is List) return List<Map<String, dynamic>>.from(data);
        } catch (_) {
          // Try the direct public route if the relay is unavailable.
        }
      }
      throw StateError('Highlights unavailable');
    } finally {
      if (client == null) transport.close();
    }
  }
}
