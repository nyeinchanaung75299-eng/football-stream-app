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
  late Future<List<Map<String, dynamic>>> rows = load();
  bool opening = false;
  Future<List<Map<String, dynamic>>>
  load() async => List<Map<String, dynamic>>.from(
    await Supabase.instance.client
        .from('highlights')
        .select(
          'id,title,thumbnail_url,video_url,stream_type,referer,origin,user_agent',
        )
        .eq('is_active', true)
        .order('sort_order')
        .order('created_at', ascending: false)
        .limit(200)
        .timeout(const Duration(seconds: 12)),
  );
  Future<void> refresh() async {
    final next = load();
    setState(() => rows = next);
    await next;
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
          onPressed: () => setState(() => rows = load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: rows,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: TextButton(
              onPressed: () => setState(() => rows = load()),
              child: const Text('Could not load highlights. Retry'),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            children: items.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No highlights published yet.'),
                    ),
                  ]
                : [
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
                  ],
          ),
        );
      },
    ),
  );
}
