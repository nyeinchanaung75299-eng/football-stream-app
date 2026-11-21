import 'package:supabase_flutter/supabase_flutter.dart';

/// Apply filters at the server and fetch every page deterministically. Server
/// row caps must not hide current matches behind older fixtures.
Future<List<Map<String, dynamic>>> loadAdminMatches(SupabaseClient db,
    {required String columns,
    bool activeOnly = false,
    bool publishedOnly = false}) async {
  final result = <Map<String, dynamic>>[];
  for (var offset = 0;; offset += 250) {
    var query = db.from('matches').select(columns).isFilter('deleted_at', null);
    if (activeOnly) query = query.eq('is_active', true);
    if (publishedOnly)
      query = query.eq('is_featured', true).eq('publish_state', 'published');
    final page = await query
        .order('kickoff_at')
        .order('id')
        .range(offset, offset + 249)
        .timeout(const Duration(seconds: 12));
    result.addAll(List<Map<String, dynamic>>.from(page));
    if (page.length < 250) return result;
    if (offset >= 20000)
      throw StateError('Too many matches. Narrow the date range.');
  }
}
