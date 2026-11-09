import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A deleted imported line is suppressed until an admin explicitly allows it.
/// This page never restores a stream URL directly or affects healthy siblings.
class SuppressedSourceLinesPage extends StatefulWidget {
  const SuppressedSourceLinesPage({super.key});

  @override
  State<SuppressedSourceLinesPage> createState() =>
      _SuppressedSourceLinesPageState();
}

class _SuppressedSourceLinesPageState extends State<SuppressedSourceLinesPage> {
  late Future<List<Map<String, dynamic>>> _rows = _load();
  String? _busyKey;

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('channel_source_line_suppressions')
        .select(
          'entry_id,channel_id,source_line_id,deleted_at,'
          'channels(name),channel_source_catalog(name)',
        )
        .order('deleted_at', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() => setState(() => _rows = _load());

  Future<void> _allowAgain(Map<String, dynamic> line) async {
    final entry = line['entry_id']?.toString() ?? '';
    final channel = line['channel_id']?.toString() ?? '';
    final sourceLine = line['source_line_id']?.toString() ?? '';
    if (entry.isEmpty || channel.isEmpty || sourceLine.isEmpty) return;
    final key = '$entry:$channel:$sourceLine';
    if (_busyKey != null) return;

    final name = (line['channels'] is Map
        ? (line['channels'] as Map)['name']
        : null)?.toString() ?? channel;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Allow source line again?'),
        content: Text(
          '$name • $sourceLine\n\n'
          'This removes the deletion block for only this source line. '
          'The next normal catalog sync may restore it. '
          'Other deleted lines stay blocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Allow again'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busyKey = key);
    try {
      final deleted = await Supabase.instance.client
          .from('channel_source_line_suppressions')
          .delete()
          .eq('entry_id', entry)
          .eq('channel_id', channel)
          .eq('source_line_id', sourceLine)
          .select('source_line_id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deleted.isEmpty
            ? 'No permission or line already allowed. Refresh and check.'
            : 'Allowed again. The next source sync can restore this line.'),
      ));
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not allow this line. Check admin access.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Deleted source lines'),
      actions: [
        IconButton(
          tooltip: 'Refresh deleted line list',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Could not load deleted lines. Retry'),
          ));
        }
        final lines = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async { _refresh(); await _rows; },
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Synced lines you deleted stay blocked by default. '
                'Allow again only if the deletion was a mistake. '
                'The line can return on the next normal sync; '
                'healthy lines continue updating.',
              ),
              const SizedBox(height: 12),
              if (lines.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No suppressed source lines'),
                  subtitle: Text('Future deleted synced lines will be listed here.'),
                ),
              for (final line in lines)
                Card(
                  child: ListTile(
                    title: Text(
                      (line['channels'] is Map
                              ? (line['channels'] as Map)['name']
                              : null)?.toString() ??
                          line['channel_id']?.toString() ?? 'Channel',
                    ),
                    subtitle: Text(
                      'Source: ${(line['channel_source_catalog'] is Map
                          ? (line['channel_source_catalog'] as Map)['name']
                          : null) ?? line['entry_id']}\n'
                      'Line ID: ${line['source_line_id']}\n'
                      'Deleted: ${DateTime.tryParse(line['deleted_at']?.toString() ?? '')?.toLocal().toString().split('.').first ?? 'unknown'}',
                    ),
                    isThreeLine: true,
                    trailing: TextButton(
                      onPressed: _busyKey == null
                          ? () => _allowAgain(line)
                          : null,
                      child: const Text('Allow again'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
