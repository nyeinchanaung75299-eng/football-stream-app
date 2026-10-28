import 'package:supabase_flutter/supabase_flutter.dart';

String _searchText(String value) => value
    .toLowerCase()
    .replaceAllMapped(RegExp(r'([a-z])([0-9])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll(RegExp(r'[\s_-]+'), ' ')
    .trim();

bool channelMatchesSearch(Map<String, dynamic> channel, String query) {
  final terms = _searchText(query).split(' ').where((s) => s.isNotEmpty);
  final text =
      _searchText('${channel['name'] ?? ''} ${channel['category'] ?? ''}');
  return terms.every(text.contains);
}

class ChannelStreamSelection {
  const ChannelStreamSelection({
    required this.channelName,
    required this.streamUrl,
    required this.streamType,
    this.referer = '',
    this.origin = '',
    this.keyId = '',
    this.keyData = '',
  });

  factory ChannelStreamSelection.fromRows(
    Map<String, dynamic> channel,
    Map<String, dynamic> line,
  ) {
    String text(String key) => line[key]?.toString().trim() ?? '';
    final url = text('stream_url');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        url.contains('\n') ||
        url.contains('\r')) {
      throw const FormatException('This channel has no valid stream URL.');
    }
    final id = text('key_id');
    final key = text('key_data');
    if (id.isEmpty != key.isEmpty) {
      throw const FormatException('This channel has an incomplete key pair.');
    }
    final declared = text('stream_type');
    return ChannelStreamSelection(
      channelName: channel['name']?.toString().trim() ?? 'Channel',
      streamUrl: url,
      streamType: const {'auto', 'hls', 'dash', 'mp4', 'flv'}.contains(declared)
          ? declared
          : 'auto',
      referer: text('referer'),
      origin: text('origin'),
      keyId: id,
      keyData: key,
    );
  }

  final String channelName, streamUrl, streamType;
  final String referer, origin, keyId, keyData;
}

class ChannelSourceService {
  ChannelSourceService(this.client);
  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> list() async {
    final rows = await client
        .from('channels')
        .select('id,name,category,image_url,is_active,sort_order')
        .order('category')
        .order('sort_order')
        .order('name')
        .timeout(const Duration(seconds: 10));
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<ChannelStreamSelection> select(Map<String, dynamic> channel) async {
    // Read canonical private settings through Admin RLS. Never save the
    // Viewer's expiring /p/ playback URL as a match's source URL.
    final rows = await client
        .from('channel_lines')
        .select('stream_url,stream_type,referer,origin,key_id,key_data')
        .eq('channel_id', channel['id'])
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at')
        .limit(1)
        .timeout(const Duration(seconds: 10));
    if (rows.isEmpty) {
      throw StateError('This channel has no active stream.');
    }
    return ChannelStreamSelection.fromRows(
      channel,
      Map<String, dynamic>.from(rows.first),
    );
  }
}
