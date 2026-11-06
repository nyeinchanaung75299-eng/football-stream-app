import 'package:supabase_flutter/supabase_flutter.dart';

/// IDs with active, explicitly saved EPG mappings. A saved mapping can exist
/// even when a regional guide feed has no programmes for the chosen day.
Set<String> savedEpgChannelIds(Iterable<Map<String, dynamic>> channels) {
  final linked = <String>{};
  for (final channel in channels) {
    if (channel['is_active'] != true) continue;
    final id = channel['id']?.toString().trim() ?? '';
    final epgId = channel['epg_id']?.toString().trim() ?? '';
    final epgSource = channel['epg_source']?.toString().trim() ?? '';
    if (id.isNotEmpty && epgId.isNotEmpty && epgSource.isNotEmpty) {
      linked.add(id);
    }
  }
  return linked;
}

/// Admin-authenticated, read-only inventory from the existing channels table.
/// Never guesses missing mappings from names or counts programme matches as
/// persisted connections. No schema changes and no database writes.
class SavedEpgLinksService {
  SavedEpgLinksService(this.client);
  final SupabaseClient client;

  Future<Set<String>> load() async {
    final rows = await client
        .from('channels')
        .select('id,is_active,epg_id,epg_source')
        .order('id')
        .limit(500)
        .timeout(const Duration(seconds: 12));
    return savedEpgChannelIds(List<Map<String, dynamic>>.from(rows));
  }
}
