import 'package:supabase_flutter/supabase_flutter.dart';

/// Public category ordering only. Stream URLs and credentials are never read.
class ChannelGroupOrderService {
  ChannelGroupOrderService(this.client);
  final SupabaseClient client;

  Future<Map<String, int>> positions() async {
    final rows = await client
        .from('channel_group_order')
        .select('category,position')
        .order('position')
        .timeout(const Duration(seconds: 10));
    return {
      for (final row in rows)
        row['category'].toString(): (row['position'] as num).toInt(),
    };
  }

  Future<List<String>> categoriesInOrder() async {
    final data = await Future.wait([
      client.from('channels').select('category').order('category'),
      client.from('channel_group_order').select('category,position').order('position'),
    ]);
    final names = <String>{
      for (final row in data[0])
        if ((row['category']?.toString() ?? '').trim().isNotEmpty)
          row['category'].toString(),
    };
    final ranked = <String, int>{
      for (final row in data[1])
        row['category'].toString(): (row['position'] as num).toInt(),
    };
    return names.toList()..sort((a, b) {
      final rank = (ranked[a] ?? 100000).compareTo(ranked[b] ?? 100000);
      return rank != 0 ? rank : a.compareTo(b);
    });
  }

  Future<void> save(List<String> orderedCategories) async {
    if (orderedCategories.toSet().length != orderedCategories.length) {
      throw ArgumentError('Channel group names must be unique.');
    }
    await client.from('channel_group_order').upsert([
      for (var index = 0; index < orderedCategories.length; index++)
        {'category': orderedCategories[index], 'position': index},
    ], onConflict: 'category').timeout(const Duration(seconds: 15));
  }
}
