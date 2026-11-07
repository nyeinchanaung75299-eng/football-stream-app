import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/channel_source_service.dart';
import '../services/connected_channel_source.dart';

class ConnectedChannelsPage extends StatefulWidget {
  const ConnectedChannelsPage({super.key});
  @override
  State<ConnectedChannelsPage> createState() => _ConnectedChannelsPageState();
}

class _ConnectedChannelsPageState extends State<ConnectedChannelsPage> {
  final service = ConnectedChannelSource();
  final search = TextEditingController();
  Timer? _debounce;
  int provider = 0, page = 0;
  String kind = '';
  bool working = false;
  late Future<Map<String, dynamic>> catalog = load();
  Future<Map<String, dynamic>> load() => service.request('catalog', {
    'provider': provider, 'kind': kind, 'query': search.text.trim(), 'page': page,
  });
  void refresh({bool resetPage = false}) {
    if (resetPage) page = 0;
    setState(() => catalog = load());
  }
  @override
  void dispose() { _debounce?.cancel(); search.dispose(); super.dispose(); }
  void notice(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
  Future<void> mutate(String action, Map<String, dynamic> fields) async {
    if (working) return;
    setState(() => working = true);
    try {
      await service.request(action, fields);
      if (mounted) refresh();
      if (action == 'sync') notice('Source checked. Connected channels updated.');
    } catch (_) { notice('Could not complete the request. Refresh before retrying.'); }
    finally { if (mounted) setState(() => working = false); }
  }
  Future<void> add(Map<String, dynamic> row, {String? channelId}) async {
    await mutate('import', {'entry_id': row['id'], if (channelId != null) 'channel_id': channelId});
  }
  Future<void> chooseExisting(Map<String, dynamic> row) async {
    try {
      final channels = await ChannelSourceService(Supabase.instance.client).list();
      if (!mounted) return;
      var query = '';
      final selected = await showModalBottomSheet<String>(context: context,
        isScrollControlled: true, showDragHandle: true, useSafeArea: true,
        builder: (sheet) => StatefulBuilder(builder: (_, update) => SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .7,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('Add line to existing channel')),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: TextField(
              decoration: const InputDecoration(hintText: 'Search channels', prefixIcon: Icon(Icons.search)),
              onChanged: (value) => update(() => query = value),
            )),
            Expanded(child: ListView(children: [
              for (final channel in channels.where((item) => channelMatchesSearch(item, query)))
                ListTile(title: Text(channel['name']?.toString() ?? 'Channel'),
                  subtitle: Text(channel['category']?.toString() ?? ''),
                  onTap: () => Navigator.pop(sheet, channel['id'].toString())),
            ])),
          ]),
        )),
      );
      if (selected != null && mounted) await add(row, channelId: selected);
    } catch (_) { notice('Could not load existing channels.'); }
  }
  Future<void> details(Map<String, dynamic> row) async {
    try {
      final response = await service.request('details', {'entry_id': row['id']});
      if (!mounted) return;
      final entry = Map<String, dynamic>.from(response['entry'] as Map);
      final lines = (entry['streams'] as List? ?? []).whereType<Map>().toList();
      await showModalBottomSheet<void>(context: context, showDragHandle: true,
        isScrollControlled: true, useSafeArea: true,
        builder: (sheet) => SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(row['name'].toString(), style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final line in lines) ListTile(contentPadding: EdgeInsets.zero,
              title: Text(line['label']?.toString() ?? 'Line'),
              subtitle: Text(line['stream_type']?.toString().toUpperCase() ?? 'AUTO'),
              trailing: PopupMenuButton<String>(tooltip: 'Copy link or headers',
                icon: const Icon(Icons.copy),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'stream_url', child: Text('Copy video URL')),
                  if (line['referer'] != null) const PopupMenuItem(value: 'referer', child: Text('Copy Referer')),
                  if (line['origin'] != null) const PopupMenuItem(value: 'origin', child: Text('Copy Origin')),
                ],
                onSelected: (field) => Clipboard.setData(ClipboardData(text: line[field]?.toString() ?? '')),
              ),
            ),
            if (lines.isNotEmpty && row['connection'] == null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Add to My Channels'),
                onPressed: () { Navigator.pop(sheet); add(row); }),
              TextButton(onPressed: () { Navigator.pop(sheet); chooseExisting(row); },
                child: const Text('Add line to existing channel')),
            ],
            if (entry['playlist_url'] != null) OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new), label: const Text('Open published playlist'),
              onPressed: () => launchUrl(Uri.parse(entry['playlist_url'].toString()),
                mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank')),
            if (lines.isEmpty && entry['playlist_url'] == null)
              const Text('This entry has no resolved native video line in the published source.'),
          ]),
        )),
      );
    } catch (_) { notice('Could not load source details.'); }
  }
  Widget entryTile(Map<String, dynamic> row) {
    final connection = row['connection'] is Map ? Map<String, dynamic>.from(row['connection'] as Map) : <String, dynamic>{};
    final count = (row['stream_count'] as num?)?.toInt() ?? 0;
    final linked = connection.isNotEmpty;
    return ListTile(dense: true,
      title: Text(row['name']?.toString() ?? 'Channel', maxLines: 2),
      subtitle: Text('Provider ${row['provider']} • ${row['category']} • '
        '${linked ? connection['source_missing'] == true ? 'Source missing' : connection['follow_updates'] == true ? 'Following' : 'Paused' : count > 0 ? '$count lines' : row['kind'] == 'playlist' ? 'Playlist' : 'Unresolved'}'),
      onTap: () => details(row),
      trailing: linked ? PopupMenuButton<String>(tooltip: 'Connection settings',
        icon: Icon(connection['follow_updates'] == true ? Icons.sync : Icons.pause_circle_outline),
        onSelected: (value) => mutate(value == 'unlink' ? 'unlink' : 'follow', {
          'entry_id': row['id'], if (value != 'unlink') 'enabled': connection['follow_updates'] != true,
        }),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'follow', child: Text(connection['follow_updates'] == true ? 'Pause updates' : 'Resume updates')),
          const PopupMenuItem(value: 'unlink', child: Text('Disconnect and keep saved channel')),
        ],
      ) : count > 0 ? IconButton(tooltip: 'Add to My Channels', icon: const Icon(Icons.add_circle_outline),
        onPressed: working ? null : () => add(row)) : const Icon(Icons.open_in_new, size: 18),
    );
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DarkByte Channels'), actions: [
      TextButton.icon(onPressed: working ? null : () => mutate('sync', const {}),
        icon: working ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync, size: 18),
        label: const Text('Sync now')),
    ]),
    body: FutureBuilder<Map<String, dynamic>>(future: catalog, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: TextButton.icon(onPressed: refresh,
        icon: const Icon(Icons.refresh), label: const Text('Could not load source. Retry')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!;
      final state = Map<String, dynamic>.from(data['state'] as Map);
      final rows = (data['entries'] as List).whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
      final checked = DateTime.tryParse(state['last_checked_at']?.toString() ?? '')?.toLocal();
      final total = (data['total'] as num?)?.toInt() ?? 0;
      return Column(children: [
        SwitchListTile.adaptive(dense: true, title: const Text('Auto-sync every 5 minutes', style: TextStyle(fontSize: 13)),
          subtitle: Text('${state['status']} • ${checked == null ? 'Not checked yet' : DateFormat('dd MMM, h:mm a').format(checked)}', style: const TextStyle(fontSize: 11)),
          value: state['enabled'] == true, onChanged: working ? null : (value) => mutate('settings', {'enabled': value})),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(controller: search,
          decoration: const InputDecoration(hintText: 'Search source channels', prefixIcon: Icon(Icons.search), isDense: true),
          onChanged: (_) { _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 350), () => refresh(resetPage: true)); })),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [
          Expanded(child: DropdownButton<int>(isExpanded: true, value: provider,
            items: [const DropdownMenuItem(value: 0, child: Text('All providers')),
              for (var i = 1; i <= 6; i++) DropdownMenuItem(value: i, child: Text('Provider $i'))],
            onChanged: (value) { provider = value ?? 0; refresh(resetPage: true); })),
          const SizedBox(width: 10),
          Expanded(child: DropdownButton<String>(isExpanded: true, value: kind,
            items: const [DropdownMenuItem(value: '', child: Text('All entries')),
              DropdownMenuItem(value: 'channel', child: Text('Channels')),
              DropdownMenuItem(value: 'event', child: Text('Live events')),
              DropdownMenuItem(value: 'video', child: Text('Videos / highlights')),
              DropdownMenuItem(value: 'playlist', child: Text('Playlists'))],
            onChanged: (value) { kind = value ?? ''; refresh(resetPage: true); })),
        ])),
        Expanded(child: RefreshIndicator(onRefresh: () async { refresh(); await catalog; },
          child: rows.isEmpty ? ListView(children: const [Padding(padding: EdgeInsets.all(20), child: Text('No source entries. Try Sync now or clear filters.'))])
            : ListView.separated(itemCount: rows.length, itemBuilder: (_, index) => entryTile(rows[index]),
                separatorBuilder: (_, __) => const Divider(height: 1)))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(onPressed: page > 0 ? () { page--; refresh(); } : null, icon: const Icon(Icons.chevron_left)),
          Text('${total == 0 ? 0 : page * 100 + 1}–${page * 100 + rows.length} of $total', style: const TextStyle(fontSize: 12)),
          IconButton(onPressed: (page + 1) * 100 < total ? () { page++; refresh(); } : null, icon: const Icon(Icons.chevron_right)),
        ]),
      ]);
    }),
  );
}
