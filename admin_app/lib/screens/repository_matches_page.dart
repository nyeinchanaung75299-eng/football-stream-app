import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/connected_channel_source.dart';
import '../widgets/repository_match_card.dart';
import 'repository_channel_updates_page.dart';

class RepositoryMatchesPage extends StatefulWidget {
  const RepositoryMatchesPage({super.key, this.onMutated});
  final VoidCallback? onMutated;
  @override
  State<RepositoryMatchesPage> createState() => _RepositoryMatchesPageState();
}

class _RepositoryMatchesPageState extends State<RepositoryMatchesPage> {
  final source = ConnectedChannelSource(source: 'repository');
  final search = TextEditingController();
  Timer? debounce;
  int page = 0;
  bool working = false;
  late Future<Map<String, dynamic>> catalog = load();
  Future<Map<String, dynamic>> load() =>
      source.request('catalog', {'query': search.text.trim(), 'page': page});
  void refresh() {
    if (mounted) setState(() => catalog = load());
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void notice(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  void copyField(String value) {
    Clipboard.setData(ClipboardData(text: value)).then(
      (_) => notice('Copied.'),
      onError: (_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Copy line'),
            content: SingleChildScrollView(child: SelectableText(value)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget copyMenu(Map line) => PopupMenuButton<String>(
        tooltip: 'Copy line',
        icon: const Icon(Icons.copy),
        onSelected: (field) => copyField(
          field == 'all'
              ? [
                  'URL: ${line['stream_url'] ?? ''}',
                  for (final pair in const {
                    'referer': 'Referer',
                    'origin': 'Origin',
                    'key_id': 'Key ID',
                    'key_data': 'Key Data',
                  }.entries)
                    if (line[pair.key]?.toString().isNotEmpty == true)
                      '${pair.value}: ${line[pair.key]}',
                ].join('\n')
              : line[field]?.toString() ?? '',
        ),
        itemBuilder: (_) => [
          const PopupMenuItem(
              value: 'stream_url', child: Text('Copy stream URL')),
          const PopupMenuItem(
              value: 'all', child: Text('Copy all line details')),
          for (final pair in const {
            'referer': 'Referer',
            'origin': 'Origin',
            'key_id': 'Key ID',
            'key_data': 'Key Data',
          }.entries)
            if (line[pair.key]?.toString().isNotEmpty == true)
              PopupMenuItem(value: pair.key, child: Text('Copy ${pair.value}')),
        ],
      );
  Future<void> sync({bool imports = false}) async {
    if (working) return;
    setState(() => working = true);
    try {
      final result = await (imports
              ? ConnectedChannelSource(source: 'repository-imports')
              : source)
          .request('sync');
      if (kIsWeb) widget.onMutated?.call();
      if (imports) {
        notice(
          'Updated ${result['updated_lines'] ?? 0} lines • Checked ${result['probed'] ?? 0} changed configurations • Repaired ${result['repaired'] ?? 0}',
        );
      } else {
        refresh();
        notice('Repository matches updated.');
      }
    } catch (_) {
      notice('Source check unavailable. The last complete catalog was kept.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> details(Map row) async {
    try {
      final data = await source.request('details', {'entry_id': row['id']});
      if (!mounted) return;
      final lines = ((data['entry'] as Map)['streams'] as List? ?? [])
          .whereType<Map>()
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['name'].toString(),
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  for (final line in lines)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(line['label']?.toString() ?? 'Line'),
                      subtitle: Text(
                        line['configuration_status'] == 'requires_drm'
                            ? 'Needs DRM configuration'
                            : '${line['stream_type']?.toString().toUpperCase()} • Video not yet verified',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          copyMenu(line),

                        ],
                      ),
                    ),
                  if (lines.isEmpty)
                    const Text(
                      'The source has not published a native video line for this match.',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      notice('Could not load match lines.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Repository Matches'),
          actions: [
            IconButton(
              tooltip: 'Sync matches',
              onPressed: working ? null : () => sync(),
              icon: const Icon(Icons.sync),
            ),
            PopupMenuButton<String>(
              onSelected: (_) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RepositoryChannelUpdatesPage(),
                ),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'imports',
                  child: Text('Channel source updates'),
                ),
              ],
            ),
          ],
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                child: TextButton(
                  onPressed: refresh,
                  child: const Text('Retry repository catalog'),
                ),
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!, state = data['state'] as Map;
            final rows = (data['entries'] as List).whereType<Map>().toList();
            rows.sort(
              (a, b) => ((a['event_meta'] as Map?)?['kickoff_at']?.toString() ??
                      '9999')
                  .compareTo(
                (b['event_meta'] as Map?)?['kickoff_at']?.toString() ?? '9999',
              ),
            );
            return Column(
              children: [
                SwitchListTile.adaptive(
                  dense: true,
                  title: const Text(
                    'Auto-sync every 5 minutes',
                    style: TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    '${state['status']} • ${data['total']} football matches',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: state['enabled'] == true,
                  onChanged: (value) async {
                    await source.request('settings', {'enabled': value});
                    if (kIsWeb) widget.onMutated?.call();
                    refresh();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      hintText: 'Search teams or leagues',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(const Duration(milliseconds: 300), () {
                        page = 0;
                        refresh();
                      });
                    },
                  ),
                ),
                if (working) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      refresh();
                      await catalog;
                    },
                    child: ListView.builder(
                      itemCount: rows.isEmpty ? 1 : rows.length,
                      itemBuilder: (_, i) {
                        if (rows.isEmpty)
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No published football fixtures. Try Sync matches.',
                            ),
                          );
                        final row = rows[i];
                        return RepositoryMatchCard(
                          entry: Map<String, dynamic>.from(row),
                          onViewLines: () => details(row),

                        );
                      },
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: page > 0
                          ? () {
                              page--;
                              refresh();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      '${page * 100 + 1}–${page * 100 + rows.length} / ${data['total']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    IconButton(
                      onPressed: (page + 1) * 100 < (data['total'] as num)
                          ? () {
                              page++;
                              refresh();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
}
