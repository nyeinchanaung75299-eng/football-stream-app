import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});
  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  late Future<List<Map<String, dynamic>>> catalog = load();
  Future<List<Map<String, dynamic>>> load() async {
    final rows = await Supabase.instance.client
        .from('channels')
        .select('id,name,category,image_url,is_active,sort_order')
        .order('category')
        .order('sort_order')
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  void refresh() => setState(() => catalog = load());
  Future<void> edit([Map<String, dynamic>? channel]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ChannelEditor(channel: channel)),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Channels'),
      actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => edit(),
      icon: const Icon(Icons.add),
      label: const Text('ADD CHANNEL'),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: catalog,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError)
          return Center(
            child: Text('Could not load channels: ${snapshot.error}'),
          );
        if (snapshot.data!.isEmpty)
          return const Center(child: Text('No channels yet.'));
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final row = snapshot.data![index];
            final image = row['image_url']?.toString() ?? '';
            return Card(
              child: ListTile(
                leading: image.startsWith('https://')
                    ? Image.network(
                        image,
                        width: 52,
                        height: 42,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv),
                      )
                    : const Icon(Icons.tv),
                title: Text(row['name']?.toString() ?? ''),
                subtitle: Text(
                  '${row['category']} • ${row['is_active'] == true ? 'Visible' : 'Hidden'}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => edit(row),
              ),
            );
          },
        );
      },
    ),
  );
}

class _Line {
  _Line([Map<String, dynamic>? row])
    : id = row?['id']?.toString(),
      label = TextEditingController(
        text: row?['label']?.toString() ?? 'Server 1',
      ),
      url = TextEditingController(text: row?['stream_url']?.toString() ?? ''),
      referer = TextEditingController(text: row?['referer']?.toString() ?? ''),
      keyId = TextEditingController(text: row?['key_id']?.toString() ?? ''),
      keyData = TextEditingController(text: row?['key_data']?.toString() ?? '');
  final String? id;
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
          .select('id,label,stream_url,referer,key_id,key_data')
          .eq('channel_id', widget.channel!['id'])
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty)
          lines.add(_Line(Map<String, dynamic>.from(rows.first)));
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
        'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
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
              TextField(
                controller: category,
                decoration: const InputDecoration(labelText: 'Category'),
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
