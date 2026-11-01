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

/// Search the channel catalog by name/category and confirmed EPG fixture teams.
/// EPG rows contain only metadata (not source URLs or playback credentials).
List<Map<String, dynamic>> searchChannelsWithEpg(
  List<Map<String, dynamic>> channels,
  List<Map<String, dynamic>> guideRows,
  String query,
) {
  final terms = _searchText(query).split(' ').where((s) => s.isNotEmpty).toList();
  if (terms.isEmpty) return channels;

  final matchedByChannel = <String, String>{};
  for (final guide in guideRows) {
    final names = '${guide['home_team'] ?? ''} ${guide['away_team'] ?? ''}';
    final normalized = _searchText(names);
    if (terms.every(normalized.contains)) {
      final id = guide['channel_id']?.toString();
      if (id != null && id.isNotEmpty) {
        matchedByChannel.putIfAbsent(id, () => names.trim());
      }
    }
  }
  final fromGuide = <Map<String, dynamic>>[];
  final fromNames = <Map<String, dynamic>>[];
  for (final channel in channels) {
    final id = channel['id']?.toString();
    final fixture = matchedByChannel[id];
    if (fixture != null) {
      fromGuide.add({...channel, 'epg_fixture': fixture});
    } else if (channelMatchesSearch(channel, query)) {
      fromNames.add(channel);
    }
  }
  return [...fromGuide, ...fromNames];
}

class ChannelStreamSelection {
  const ChannelStreamSelection({
    required this.channelId,
    required this.channelLineId,
    required this.channelName,
    required this.lineLabel,
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
    final channelId = channel['id']?.toString().trim() ?? '';
    final channelLineId = text('id');
    if (channelId.isEmpty) {
      throw const FormatException('This channel is incomplete.');
    }
    final declared = text('stream_type');
    return ChannelStreamSelection(
      channelId: channelId,
      channelLineId: channelLineId.isEmpty ? null : channelLineId,
      channelName: channel['name']?.toString().trim() ?? 'Channel',
      lineLabel: text('label').isEmpty ? 'Line' : text('label'),
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

  final String channelId, channelName, lineLabel;
  final String? channelLineId;
  final String streamUrl, streamType;
  final String referer, origin, keyId, keyData;

  String get displayLabel => lineLabel == 'Line'
      ? channelName
      : '$channelName • $lineLabel';
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

  /// Load verified EPG channel-to-football associations once for picker search.
  /// The associated fixtures are published, and playback details stay private.
  Future<List<Map<String, dynamic>>> listEpgFixtureChannels() async {
    final since = DateTime.now().toUtc().subtract(const Duration(days: 1));
    final guideRows = await client
        .from('nca_epg_auto_match_channels')
        .select('match_id,channel_id,programme_start')
        .gte('programme_start', since.toIso8601String())
        .order('programme_start', ascending: false)
        .limit(500)
        .timeout(const Duration(seconds: 12));
    final guide = List<Map<String, dynamic>>.from(guideRows);
    if (guide.isEmpty) return [];

    final matches = await client
        .from('matches')
        .select('id,home_team,away_team')
        .inFilter('id', guide.map((r) => r['match_id'].toString()).toSet().toList())
        .eq('is_active', true)
        .eq('publish_state', 'published')
        .limit(500)
        .timeout(const Duration(seconds: 12));
    final byId = {
      for (final m in List<Map<String, dynamic>>.from(matches))
        m['id'].toString(): m,
    };
    return [
      for (final row in guide)
        if (byId.containsKey(row['match_id']?.toString()))
          {
            'channel_id': row['channel_id'],
            'home_team': byId[row['match_id'].toString()]!['home_team'],
            'away_team': byId[row['match_id'].toString()]!['away_team'],
          }
    ];
  }

  Future<ChannelStreamSelection> select(Map<String, dynamic> channel) async {
    // Read canonical private settings through Admin RLS. Never save the
    // Viewer's expiring /p/ playback URL as a match's source URL.
    final rows = await client
        .from('channel_lines')
        .select('id,label,stream_url,stream_type,referer,origin,key_id,key_data')
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
