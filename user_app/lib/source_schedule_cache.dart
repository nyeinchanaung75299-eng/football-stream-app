import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'football_english.dart';

class SourceScheduleCache {
  const SourceScheduleCache._();

  static String _cacheKey(String name) => 'viewer_source_cache_v1_$name';

  // Store public display/schedule data only. Provider stream credentials,
  // DRM information and headers must never be written to browser storage.
  static dynamic _safeSourceCacheValue(dynamic value) {
    if (value is List) return value.map(_safeSourceCacheValue).toList();
    if (value is Map) {
      const blocked = <String>{
        'stream_url',
        'url',
        'key_id',
        'key_data',
        'token',
        'headers',
        'authorization',
        'cookie',
        'license_url',
        'drm',
        'stream_links',
        'secret',
        'access_token',
        'refresh_token',
      };
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!blocked.contains(entry.key.toString().toLowerCase()))
            entry.key.toString(): _safeSourceCacheValue(entry.value),
      };
    }
    return value;
  }

  static Future<void> save(
    String source,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(source),
        jsonEncode({
          'fetched_at': DateTime.now().toUtc().toIso8601String(),
          'matches': _safeSourceCacheValue(rows),
        }),
      );
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> load(String requested) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(requested));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['matches'] is! List) return null;
      final fetched = DateTime.tryParse(
        decoded['fetched_at']?.toString() ?? '',
      );
      if (fetched == null ||
          DateTime.now().toUtc().difference(fetched.toUtc()) >
              const Duration(minutes: 20)) {
        return null;
      }
      return (decoded['matches'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .map((row) => englishSourceMatch(row, requested))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
