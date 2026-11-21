import 'function_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HighlightsService {
  const HighlightsService();
  Future<void> save(
      Map<String, dynamic> entry, Map<String, dynamic> line) async {
    final uri = Uri.tryParse(line['stream_url']?.toString() ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !const {'hls', 'dash', 'mp4'}.contains(line['stream_type'])) {
      throw const FormatException('No supported direct highlight link.');
    }
    await Supabase.instance.client
        .from('highlights')
        .upsert({
          'title': entry['title'],
          'thumbnail_url': entry['thumbnail_url'],
          'video_url': uri.toString(),
          'stream_type': line['stream_type'],
          'referer': line['referer'],
          'origin': line['origin'],
          'user_agent': line['user_agent'],
          'source_provider': provider,
          'source_entry_id': entry['id'],
          'source_line_id': line['id'],
          'is_active': true,
        }, onConflict: 'source_provider,source_entry_id,source_line_id')
        .select('id')
        .single()
        .timeout(const Duration(seconds: 15));
  }

  Future<List<Map<String, dynamic>>> saved(
          {int offset = 0, int limit = 50}) async =>
      List<Map<String, dynamic>>.from(await Supabase.instance.client
          .from('highlights')
          .select('id,title,video_url,is_active')
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + limit - 1)
          .timeout(const Duration(seconds: 15)));
  Future<void> remove(String id) async {
    final rows = await Supabase.instance.client
        .from('highlights')
        .delete()
        .eq('id', id)
        .select('id')
        .timeout(const Duration(seconds: 15));
    if (rows.length != 1)
      throw StateError('Highlight was not deleted. Refresh and retry.');
  }

  static const provider = 'dasfootball';

  Future<Map<String, dynamic>> request(String action,
      [Map<String, dynamic> fields = const {}]) async {
    final result = await FunctionGateway.invoke('source-match-list', body: {
      'source': 'highlights',
      'provider': provider,
      'action': action,
      ...fields,
    });
    if (result is! Map ||
        result['source'] != 'highlights' ||
        result['provider'] != provider) {
      throw const FormatException(
          'The server returned a different highlights source.');
    }
    return Map<String, dynamic>.from(result);
  }
}

List<Map<String, dynamic>> highlightMaps(dynamic value) => value is List
    ? value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList()
    : [];

bool highlightMatchesQuery(Map<String, dynamic> row, String query) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final text = '${row['title']} ${row['provider']}'.toLowerCase();
  return words.every(text.contains);
}

String highlightCopyDetails(Map<String, dynamic> line) => [
      line['stream_url']?.toString() ?? '',
      for (final field in ['referer', 'origin', 'user_agent'])
        if ((line[field]?.toString() ?? '').isNotEmpty)
          '${{
            'referer': 'Referer',
            'origin': 'Origin',
            'user_agent': 'User-Agent'
          }[field]}: ${line[field]}',
    ].join('\n');
