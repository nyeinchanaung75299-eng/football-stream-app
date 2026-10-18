import 'package:supabase_flutter/supabase_flutter.dart';

import 'manual_source_url.dart';

const _libraryColumns =
    'id,label,stream_type,stream_url,referer,origin,last_used_at,created_at,updated_at';

class StreamLibraryEntry {
  const StreamLibraryEntry({
    required this.id,
    required this.label,
    required this.streamUrl,
    this.referer,
    this.origin,
    this.lastUsedAt,
  });

  factory StreamLibraryEntry.fromMap(Map<String, dynamic> row) {
    String? optional(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return StreamLibraryEntry(
      id: row['id'].toString(),
      label: row['label'].toString(),
      streamUrl: row['stream_url'].toString(),
      referer: optional(row['referer']),
      origin: optional(row['origin']),
      lastUsedAt: DateTime.tryParse(row['last_used_at']?.toString() ?? ''),
    );
  }

  final String id;
  final String label;
  final String streamUrl;
  final String? referer;
  final String? origin;
  final DateTime? lastUsedAt;

  Map<String, dynamic> toPlaybackLine() => {
    'label': label,
    'url': streamUrl,
    'stream_type': 'hls',
    'resolution': 'HLS',
    'referer': referer,
    'origin': origin,
  };
}

String? validateHlsLibraryInput({
  required String label,
  required String streamUrl,
  String referer = '',
  String origin = '',
}) {
  final cleanLabel = label.trim();
  if (cleanLabel.isEmpty || cleanLabel.length > 120) {
    return 'Enter a server name between 1 and 120 characters.';
  }

  final url = streamUrl.trim();
  final detected = detectManualStreamType(url);
  if (!isValidManualStreamUrl(url, streamType: 'hls') ||
      (detected != null && detected != 'hls')) {
    return 'The Library accepts only an authorized HLS / M3U8 URL.';
  }

  for (final header in [referer.trim(), origin.trim()]) {
    if (header.isEmpty) continue;
    final parsed = Uri.tryParse(header);
    if (header.length > 2048 ||
        header.contains('\n') ||
        header.contains('\r') ||
        parsed == null ||
        !const {'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      return 'Referer and Origin must be valid HTTP(S) URLs.';
    }
  }
  return null;
}

Map<String, dynamic> streamLibraryPayload({
  required String label,
  required String streamUrl,
  String referer = '',
  String origin = '',
}) {
  String? optional(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  return {
    'label': label.trim(),
    'stream_type': 'hls',
    'stream_url': streamUrl.trim(),
    'referer': optional(referer),
    'origin': optional(origin),
  };
}

String safeStreamLocation(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return 'Private HLS stream';
  final path = uri.path.isEmpty ? '/' : uri.path;
  final shown = '${uri.host}$path';
  return shown.length <= 90 ? shown : '${shown.substring(0, 87)}…';
}

class StreamLibraryService {
  StreamLibraryService(this._client);

  final SupabaseClient _client;

  Future<List<StreamLibraryEntry>> list() async {
    final rows = await _client
        .from('stream_library')
        .select(_libraryColumns)
        .order('last_used_at', ascending: false, nullsFirst: false)
        .order('updated_at', ascending: false)
        .timeout(const Duration(seconds: 10));
    return List<Map<String, dynamic>>.from(rows)
        .map(StreamLibraryEntry.fromMap)
        .toList(growable: false);
  }

  Future<StreamLibraryEntry> save({
    required String label,
    required String streamUrl,
    String referer = '',
    String origin = '',
  }) async {
    final payload = streamLibraryPayload(
      label: label,
      streamUrl: streamUrl,
      referer: referer,
      origin: origin,
    );
    final row = await _client
        .from('stream_library')
        .upsert(payload, onConflict: 'fingerprint')
        .select(_libraryColumns)
        .single()
        .timeout(const Duration(seconds: 12));
    return StreamLibraryEntry.fromMap(row);
  }

  Future<void> markUsed(String id) async {
    await _client
        .from('stream_library')
        .update({'last_used_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .timeout(const Duration(seconds: 10));
  }

  Future<void> delete(String id) async {
    await _client
        .from('stream_library')
        .delete()
        .eq('id', id)
        .timeout(const Duration(seconds: 10));
  }
}
