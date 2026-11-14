import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/channel_source_service.dart';
import '../services/channel_group_order_service.dart';
import 'channel_group_order_page.dart';
import '../widgets/channel_search_field.dart';
import 'live_links_page.dart';

const channelGroupPresets = <String>[
  'beIN Sports',
  'UFC',
  'Travel',
  'Sky Sports',
  'DAZN',
  'ESPN',
  'Ziggo Sport',
  'Eleven Sports',
  'Setanta Sports',
  'NBC / USA / Peacock',
  'Willow / Cricket',
  'Uncategorized',
  'TNT Sports',
  'Fubo',
  'FanCode',
  'CazéTV',
  'Arena Sports',
  'FOX Sports',
  'D Sports',
  'TSN',
  'SporTV',
  'SPOTV',
  'Premiere',
  'Premier Sports',
  'CBS Sports',
  'Sport 1 / 2',
  'Nova Sport',
  'Eurosport',
  'JOJ Sport',
  'ČT Sport',
  'Sportdigital',
  'NBA',
  'Tennis',
  'Willow Cricket',
  'Motorsports',
  'Combat Sports',
  'Regional Sports',
  'SportsStars',
  'M-Sports',
  'Monomax Sports',
  'RTVS Sport',
  'Events / Unverified',
  'General TV',
  'Movies & Entertainment',
  'Documentaries',
  'Music',
];

const channelQuickGroups = <String>[
  'All', 'beIN Sports', 'TNT Sports', 'Fubo', 'FanCode',
  'CazéTV', 'Arena Sports', 'FOX Sports', 'TSN',
];

String catalogGroup(Map<String, dynamic> channel) {
  final value = channel['category']?.toString().trim() ?? '';
  return value.isEmpty ? 'Other' : value;
}

/// Dedicated new-channel form; existing channels stay unchanged until Save.
class ChannelUploadPage extends StatelessWidget {
  const ChannelUploadPage({super.key});

  @override
  Widget build(BuildContext context) => const _ChannelEditor();
}

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key, this.embedded = false, this.initialQuery = ''});
  final String initialQuery;

  /// Dashboard uses the same catalog in its persistent bottom navigation.
  /// Keep the standalone page for existing deep links and control cards.
  final bool embedded;

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  final search = TextEditingController();
  String? addingChannelId;
  String selectedGroup = 'All';
  late Future<List<Map<String, dynamic>>> catalog = load();
  Future<List<Map<String, dynamic>>> load() =>
      ChannelSourceService(Supabase.instance.client).list();

  Map<String, int> groupPositions = const {};
  @override
  void initState() {
    super.initState();
    search.text = widget.initialQuery;
    _loadGroupPositions();
  }

  Future<void> _loadGroupPositions() async {
    try {
      final positions = await ChannelGroupOrderService(Supabase.instance.client).positions();
      if (mounted) setState(() => groupPositions = positions);
    } catch (_) {
      // Fall back to legacy preset ordering if the network is unavailable.
    }
  }

  Future<void> _reorderGroups() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChannelGroupOrderPage()),
    );
    if (saved == true) {
      await _loadGroupPositions();
      refresh();
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> addToMatch(Map<String, dynamic> channel) async {
    if (addingChannelId != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => addingChannelId = channel['id'].toString());
    try {
      final selected =
          await ChannelSourceService(Supabase.instance.client).select(channel);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => LiveLinksPage(initialChannel: selected),
      ));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not load this channel. Please retry.')),
        );
    } finally {
      if (mounted) setState(() => addingChannelId = null);
    }
  }

  void refresh() {
    setState(() {
      catalog = load();
    });
    _loadGroupPositions();
  }

  Future<void> deleteChannel(Map<String, dynamic> channel) async {
    if (addingChannelId != null) return;
    final id = channel['id']?.toString();
    if (id == null || id.isEmpty) return;
    final name = channel['name']?.toString() ?? 'this channel';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete TV channel?'),
        content: Text('Permanently delete "$name", its stream lines and linked match lines? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => addingChannelId = id);
    try {
      await Supabase.instance.client.from('channels').delete().eq('id', id);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete channel. Please retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => addingChannelId = null);
    }
  }

  Future<void> edit([Map<String, dynamic>? channel]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ChannelEditor(channel: channel)),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (widget.embedded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'My Channels',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh channels',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: 'Reorder channel groups',
                  onPressed: _reorderGroups,
                  icon: const Icon(Icons.swap_vert_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        ChannelSearchField(
          controller: search,
          onChanged: (_) => setState(() {}),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: catalog,
            builder: (context, snapshot) {
              if (!snapshot.hasData && !snapshot.hasError) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('Could not load channels: ${snapshot.error}'),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const Center(child: Text('No channels yet.'));
              }
              final groupCounts = <String, int>{};
              for (final channel in snapshot.data!) {
                final group = catalogGroup(channel);
                groupCounts[group] = (groupCounts[group] ?? 0) + 1;
              }
              final availableGroups = groupCounts.keys.toList()
                ..sort((a, b) {
                  final ai = channelGroupPresets.indexOf(a);
                  final bi = channelGroupPresets.indexOf(b);
                  final ar = groupPositions[a] ?? (ai < 0 ? 999 : ai);
                  final br = groupPositions[b] ?? (bi < 0 ? 999 : bi);
                  return ar.compareTo(br) != 0
                      ? ar.compareTo(br)
                      : a.compareTo(b);
                });
              final activeGroup =
                  groupCounts.containsKey(selectedGroup) ? selectedGroup : 'All';
              final rows = snapshot.data!
                  .where((r) =>
                      channelMatchesSearch(r, search.text) &&
                      (activeGroup == 'All' ||
                          catalogGroup(r) == activeGroup))
                  .toList();
              rows.sort((a, b) {
                final byGroup =
                    availableGroups.indexOf(catalogGroup(a)).compareTo(
                      availableGroups.indexOf(catalogGroup(b)));
                if (byGroup != 0) return byGroup;
                final byOrder = ((a['sort_order'] as num?)?.toInt() ?? 0)
                    .compareTo((b['sort_order'] as num?)?.toInt() ?? 0);
                return byOrder != 0
                    ? byOrder
                    : (a['name']?.toString() ?? '')
                        .compareTo(b['name']?.toString() ?? '');
              });
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('admin-group-$activeGroup'),
                      value: activeGroup,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Channel group',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'All',
                          child: Text('All Channels (${snapshot.data!.length})'),
                        ),
                        for (final group in availableGroups)
                          DropdownMenuItem(
                            value: group,
                            child: Text('$group (${groupCounts[group]})'),
                          ),
                      ],
                      onChanged: (group) {
                        if (group != null) setState(() => selectedGroup = group);
                      },
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final group in channelQuickGroups)
                          if (group == 'All' || groupCounts.containsKey(group))
                            Padding(
                              padding: const EdgeInsets.only(right: 7),
                              child: ChoiceChip(
                                label: Text(group == 'All'
                                    ? 'All (${snapshot.data!.length})'
                                    : '$group (${groupCounts[group]})'),
                                selected: activeGroup == group,
                                onSelected: (_) =>
                                    setState(() => selectedGroup = group),
                              ),
                            ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('No matching channels.'))
                        : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final image = row['image_url']?.toString() ?? '';
                  final group = catalogGroup(row);
                  final showHeading = index == 0 ||
                      catalogGroup(rows[index - 1]) != group;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeading)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(7, 10, 7, 7),
                          child: Text(
                            '$group (${rows.where((r) => catalogGroup(r) == group).length})',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      Card(
                    child: ListTile(
                      enabled: addingChannelId == null,
                      leading: image.startsWith('https://')
                          ? Image.network(
                              image,
                              width: 52,
                              height: 42,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.tv),
                            )
                          : const Icon(Icons.tv),
                      title: Text(row['name']?.toString() ?? ''),
                      subtitle: Text(
                        '${row['category']} • ${row['is_active'] == true ? 'Visible' : 'Hidden'}',
                      ),
                      trailing: addingChannelId == row['id'].toString()
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : PopupMenuButton<String>(
                              tooltip: 'Channel actions',
                              enabled: addingChannelId == null,
                              onSelected: (action) {
                                if (action == 'match') {
                                  addToMatch(row);
                                } else if (action == 'delete') {
                                  deleteChannel(row);
                                } else {
                                  edit(row);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'match',
                                  child: Text('Add to match'),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit channel'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete Channel'),
                                ),
                              ],
                            ),
                      onTap: () => edit(row),
                      ),
                      ),
                    ],
                  );
                },
              ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Edit & Delete Channels'),
              actions: [
                IconButton(
                  tooltip: 'Reorder channel groups',
                  onPressed: _reorderGroups,
                  icon: const Icon(Icons.swap_vert_rounded),
                ),
                IconButton(
                  tooltip: 'Refresh channels',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addingChannelId == null ? () => edit() : null,
        icon: const Icon(Icons.add),
        label: const Text('ADD CHANNEL'),
      ),
      body: content,
    );
  }
}

class _Line {
  _Line([Map<String, dynamic>? row])
    : id = row?['id']?.toString(),
      originalUrl = row?['stream_url']?.toString() ?? '',
      configurationStatus = row?['configuration_status']?.toString() ?? 'unverified',
      label = TextEditingController(
        text: row?['label']?.toString() ?? 'Server 1',
      ),
      url = TextEditingController(text: row?['stream_url']?.toString() ?? ''),
      referer = TextEditingController(text: row?['referer']?.toString() ?? ''),
      keyId = TextEditingController(text: row?['key_id']?.toString() ?? ''),
      keyData = TextEditingController(text: row?['key_data']?.toString() ?? '');
  final String? id;
  final String originalUrl, configurationStatus;
  final TextEditingController label, url, referer, keyId, keyData;
  void dispose() {
    for (final field in [label, url, referer, keyId, keyData]) {
      field.dispose();
    }
  }
}

class _ChannelEditor extends StatefulWidget {
  const _ChannelEditor({this.channel});
  final Map<String, dynamic>? channel;
  @override
  State<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<_ChannelEditor> {
  late final name = TextEditingController(
    text: widget.channel?['name']?.toString(),
  );
  late final category = TextEditingController(
    text: widget.channel?['category']?.toString(),
  );
  late final image = TextEditingController(
    text: widget.channel?['image_url']?.toString(),
  );
  late final order = TextEditingController(
    text: widget.channel?['sort_order']?.toString() ?? '0',
  );
  late bool active = widget.channel?['is_active'] != false;
  final lines = <_Line>[];
  final removed = <_Line>[];
  bool loading = false, loadFailed = false, saving = false;
  @override
  void initState() {
    super.initState();
    if (widget.channel == null) {
      lines.add(_Line());
    } else {
      loading = true;
      unawaited(loadLines());
    }
  }

  Future<void> loadLines() async {
    try {
      final rows = await Supabase.instance.client
          .from('channel_lines')
          .select('id,label,stream_url,referer,key_id,key_data,configuration_status')
          .eq('channel_id', widget.channel!['id'])
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        lines.addAll(
          rows.map((row) => _Line(Map<String, dynamic>.from(row))),
        );
        if (lines.isEmpty) lines.add(_Line());
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        loadFailed = true;
      });
      notice('Could not load channel lines: $error');
    }
  }

  @override
  void dispose() {
    for (final field in [name, category, image, order]) {
      field.dispose();
    }
    for (final line in [...lines, ...removed]) {
      line.dispose();
    }
    super.dispose();
  }

  bool valid(String value, {bool optional = false}) {
    if (optional && value.isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  void notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> save() async {
    if (loading || loadFailed || saving) return;
    if (name.text.trim().isEmpty ||
        category.text.trim().isEmpty ||
        lines.isEmpty ||
        !valid(image.text.trim(), optional: true) ||
        (image.text.trim().isNotEmpty &&
            !image.text.trim().startsWith('https://')) ||
        lines.any(
          (line) =>
              line.label.text.trim().isEmpty ||
              !valid(line.url.text.trim()) ||
              !valid(line.referer.text.trim(), optional: true) ||
              (line.keyId.text.trim().isEmpty !=
                  line.keyData.text.trim().isEmpty),
        )) {
      notice('Add a name, category and valid stream URL. Keys must be a pair.');
      return;
    }
    setState(() => saving = true);
    final db = Supabase.instance.client;
    String? createdId;
    try {
      final fields = {
        'name': name.text.trim(),
        'category': category.text.trim(),
        'category_locked': true,
        'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
        if (image.text.trim() !=
            (widget.channel?['image_url']?.toString() ?? '').trim())
          'image_locked': true,
        'sort_order': int.tryParse(order.text) ?? 0,
        'is_active': widget.channel == null ? false : active,
      };
      final id =
          widget.channel?['id']?.toString() ??
          (await db.from('channels').insert(fields).select('id').single())['id']
              .toString();
      if (widget.channel == null)
        createdId = id;
      else
        await db.from('channels').update(fields).eq('id', id);
      final saved = <String>{};
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        final referer = line.referer.text.trim();
        final url = line.url.text.trim();
        final type = url.contains('.m3u8')
            ? 'hls'
            : url.contains('.mpd')
            ? 'dash'
            : url.contains('.mp4')
            ? 'mp4'
            : url.contains('.flv')
            ? 'flv'
            : 'auto';
        final fields = {
          'channel_id': id,
          'label': line.label.text.trim(),
          'stream_url': url,
          'stream_type': type,
          'referer': referer.isEmpty ? null : referer,
          'origin': referer.isEmpty ? null : Uri.parse(referer).origin,
          'key_id': line.keyId.text.trim().isEmpty
              ? null
              : line.keyId.text.trim(),
          'key_data': line.keyData.text.trim().isEmpty
              ? null
              : line.keyData.text.trim(),
          'sort_order': index,
          'is_active': true,
          'health_status': 'unknown',
          'health_latency_ms': null,
          'health_http_status': null,
          'last_checked_at': null,
          'configuration_status': line.keyId.text.trim().isNotEmpty && line.keyData.text.trim().isNotEmpty
              ? 'configured'
              : (line.url.text.trim() == line.originalUrl ? line.configurationStatus : 'unverified'),
        };
        if (line.id == null) {
          final row = await db
              .from('channel_lines')
              .insert(fields)
              .select('id')
              .single();
          saved.add(row['id'].toString());
        } else {
          await db.from('channel_lines').update(fields).eq('id', line.id!);
          saved.add(line.id!);
        }
      }
      if (widget.channel != null) {
        final old = await db
            .from('channel_lines')
            .select('id')
            .eq('channel_id', id);
        for (final row in old) {
          if (!saved.contains(row['id'].toString())) {
            await db.from('channel_lines').delete().eq('id', row['id']);
          }
        }
      } else if (active) {
        await db.from('channels').update({'is_active': true}).eq('id', id);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (createdId != null) {
        try {
          await db.from('channels').delete().eq('id', createdId);
        } catch (_) {}
      }
      if (mounted) notice('Save failed: $error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.channel == null ? 'Add Channel' : 'Edit Channel'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Channel name'),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('category-preset-${category.text}'),
                value: channelGroupPresets.contains(category.text.trim())
                    ? category.text.trim()
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Channel group',
                ),
                hint: const Text('Choose a network group'),
                items: [
                  for (final group in channelGroupPresets)
                    DropdownMenuItem(value: group, child: Text(group)),
                ],
                onChanged: (group) {
                  if (group != null) setState(() => category.text = group);
                },
              ),
              TextField(
                controller: category,
                decoration: const InputDecoration(
                  labelText: 'Category (custom if needed)',
                ),
              ),
              TextField(
                controller: image,
                decoration: const InputDecoration(
                  labelText: 'Image URL (HTTPS)',
                ),
              ),
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Order'),
              ),
              SwitchListTile(
                title: const Text('Visible to viewers'),
                value: active,
                onChanged: (value) => setState(() => active = value),
              ),
              for (var i = 0; i < lines.length; i++)
                Card(
                  key: ObjectKey(lines[i]),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: lines[i].url,
                          decoration: const InputDecoration(
                            labelText: 'Stream URL (M3U8 / MPD / MP4)',
                          ),
                        ),
                        TextField(
                          controller: lines[i].referer,
                          decoration: const InputDecoration(
                            labelText: 'Referer (optional)',
                          ),
                        ),
                        TextField(
                          controller: lines[i].keyId,
                          decoration: const InputDecoration(
                            labelText: 'Key One / ClearKey ID (optional)',
                          ),
                        ),
                        TextField(
                          controller: lines[i].keyData,
                          decoration: const InputDecoration(
                            labelText: 'Key Two / ClearKey value (optional)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving || loadFailed ? null : save,
                child: Text(saving ? 'SAVING…' : 'SAVE CHANNEL'),
              ),

            ],
          ),
  );
}
