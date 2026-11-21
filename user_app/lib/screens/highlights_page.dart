import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../native_player.dart';

/// Loaded on demand; there is no background highlights polling.
class HighlightsPage extends StatefulWidget {
  const HighlightsPage({super.key});
  @override
  State<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends State<HighlightsPage> {
  final items = <Map<String, dynamic>>[];
  bool opening = false, loading = false, hasMore = true;
  String? error;
  static const pageSize = 50;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final offset = more ? items.length : 0;
      final next = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('highlights')
            .select(
              'id,title,thumbnail_url,video_url,stream_type,referer,origin,user_agent',
            )
            .eq('is_active', true)
            .order('sort_order')
            .order('created_at', ascending: false)
            .order('id')
            .range(offset, offset + pageSize - 1)
            .timeout(const Duration(seconds: 12)),
      );
      if (!mounted) return;
      setState(() {
        if (!more) items.clear();
        final ids = items.map((r) => r['id']).toSet();
        items.addAll(next.where((r) => ids.add(r['id'])));
        hasMore = next.length == pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load highlights. Retry');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> play(Map<String, dynamic> row) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await NativePlayer.open(
        context: context,
        title: row['title']?.toString(),
        selectedIndex: 0,
        sources: [
          {
            'id': row['id'],
            'label': 'Highlights',
            'url': row['video_url'],
            'streamType': row['stream_type'] ?? 'auto',
            'referer': row['referer'] ?? '',
            'origin': row['origin'] ?? '',
            'userAgent': row['user_agent'] ?? '',
          },
        ],
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this highlight. Try again later.'),
          ),
        );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Highlights'),
      actions: [
        IconButton(
          tooltip: 'Refresh highlights',
          onPressed: loading ? null : refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            TextButton(
              onPressed: loading ? null : () => refresh(more: items.isNotEmpty),
              child: Text(error!),
            ),
          if (!loading && error == null && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No highlights published yet.'),
            ),
          for (final row in items)
            Card(
              child: ListTile(
                title: Text(row['title']?.toString() ?? 'Highlights'),
                leading: row['thumbnail_url'] == null
                    ? const Icon(Icons.movie_outlined)
                    : Image.network(
                        row['thumbnail_url'].toString(),
                        width: 64,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.movie_outlined),
                      ),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: opening ? null : () => play(row),
              ),
            ),
          if (hasMore && items.isNotEmpty)
            OutlinedButton(
              onPressed: loading ? null : () => refresh(more: true),
              child: const Text('Load more highlights'),
            ),
        ],
      ),
    ),
  );
}
