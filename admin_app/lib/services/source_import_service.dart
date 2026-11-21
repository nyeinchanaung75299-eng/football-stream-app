import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// A retry of an uncertain write retains its UUID and exact payload. The DB
/// serializes imports on the match and commits the selected batch atomically.
class SourceImportService {
  SourceImportService(this.db);
  final SupabaseClient db;
  final _requests = <String, String>{};
  Future<Map<String, dynamic>> save(
      {required String matchId,
      required String source,
      required Map<String, dynamic> room,
      required List<Map<String, dynamic>> lines}) async {
    final identity = jsonEncode([matchId, source, room, lines]);
    final requestId = _requests.putIfAbsent(identity, () => const Uuid().v4());
    final response = await db.rpc('import_match_source_lines', params: {
      'p_match_id': matchId,
      'p_source': source,
      'p_room': room,
      'p_lines': lines,
      'p_request_id': requestId,
    }).timeout(const Duration(seconds: 20));
    if (response is! Map || response['ok'] != true)
      throw StateError('Import was not confirmed.');
    _requests.remove(identity);
    return Map<String, dynamic>.from(response);
  }
}
