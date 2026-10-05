import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLinksPage extends StatefulWidget {
  const LiveLinksPage({super.key, this.initialMatchId});

  final String? initialMatchId;

  @override
  State<LiveLinksPage> createState() => _LiveLinksPageState();
}

class _LiveLinksPageState extends State<LiveLinksPage> {
  final serverName = TextEditingController(text: 'Server 1');
  final link = TextEditingController();
  final referer = TextEditingController();
  final origin = TextEditingController();
  final keyId = TextEditingController();
  final keyData = TextEditingController();
  final webViewUrl = TextEditingController();

  String streamType = 'auto';
  String? matchId;
  bool useWebView = false;
  bool loading = false;

  final streamTypes = const <String, String>{
    'auto': 'Auto / Direct',
    'hls': 'HLS (.m3u8)',
    'dash': 'DASH (.mpd)',
    'flv': 'FLV (.flv)',
    'mp4': 'MP4 / Progressive',
  };

  @override
  void initState() {
    super.initState();
    matchId = widget.initialMatchId;
  }

  String? nullable(String value) {
    final v = value.trim();
    return v.isEmpty ? null : v;
  }

  String detectStreamType(String value, {String fallback = 'auto'}) {
    final v = value.trim().toLowerCase();
    if (v.contains('.m3u8')) return 'hls';
    if (v.contains('.mpd')) return 'dash';
    if (v.contains('.flv')) return 'flv';
    if (v.contains('.mp4')) return 'mp4';
    return fallback;
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('id,home_team,away_team,league')
        .order('kickoff_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> loadLinks() async {
    if (matchId == null) return [];
    final data = await Supabase.instance.client
        .from('stream_links')
        .select()
        .eq('match_id', matchId!)
        .order('sort_order')
        .order('created_at');
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> addLink() async {
    if (matchId == null) {
      message('Select a match first.');
      return;
    }

    if (!useWebView && link.text.trim().isEmpty) {
      message('Paste a stream URL.');
      return;
    }

    if (useWebView && webViewUrl.text.trim().isEmpty) {
      message('Paste a WebView URL.');
      return;
    }

    setState(() => loading = true);

    try {
      final name = serverName.text.trim().isEmpty
          ? 'Server'
          : serverName.text.trim();

      final effectiveType = useWebView
          ? 'auto'
          : detectStreamType(link.text, fallback: streamType);

      await Supabase.instance.client.from('stream_links').insert({
        'match_id': matchId,
        'label': name,
        'resolution': name,
        'stream_type': effectiveType,
        'stream_url': useWebView ? '' : link.text.trim(),
        'referer': nullable(referer.text),
        'origin': nullable(origin.text),
        'key_id': !useWebView && effectiveType == 'dash'
            ? nullable(keyId.text)
            : null,
        'key_data': !useWebView && effectiveType == 'dash'
            ? nullable(keyData.text)
            : null,
        'use_webview': useWebView,
        'webview_url': useWebView ? webViewUrl.text.trim() : null,
        'send_notification': false,
        'is_active': true,
      });

      if (!mounted) return;

      message('Server added.');
      serverName.text = 'Server 1';
      link.clear();
      referer.clear();
      origin.clear();
      keyId.clear();
      keyData.clear();
      webViewUrl.clear();
      streamType = 'auto';
      useWebView = false;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      message(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deleteLink(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete server?'),
        content: const Text(
          'Only this link/server will be deleted. The match will stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await Supabase.instance.client
        .from('stream_links')
        .delete()
        .eq('id', id);

    if (mounted) {
      message('Server deleted.');
      setState(() {});
    }
  }

  Future<void> setActive(String id, bool value) async {
    await Supabase.instance.client
        .from('stream_links')
        .update({'is_active': value})
        .eq('id', id);

    if (mounted) setState(() {});
  }

  Future<void> editLink(Map<String, dynamic> row) async {
    final name = TextEditingController(
      text: '${row['label'] ?? row['resolution'] ?? 'Server'}',
    );
    final url = TextEditingController(text: '${row['stream_url'] ?? ''}');
    final ref = TextEditingController(text: '${row['referer'] ?? ''}');
    final org = TextEditingController(text: '${row['origin'] ?? ''}');
    final kid = TextEditingController(text: '${row['key_id'] ?? ''}');
    final key = TextEditingController(text: '${row['key_data'] ?? ''}');
    final webUrl = TextEditingController(text: '${row['webview_url'] ?? ''}');

    String type = (row['stream_type'] ?? 'auto').toString();
    if (!streamTypes.containsKey(type)) type = 'auto';
    bool web = row['use_webview'] == true;

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Edit Server',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Server name',
                        hintText: 'Main / Backup / Server 1',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Stream type',
                      ),
                      items: streamTypes.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: web
                          ? null
                          : (v) => setSheetState(() => type = v ?? 'auto'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: url,
                      enabled: !web,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (value) {
                        final detected = detectStreamType(value);
                        if (detected != 'auto' && detected != type) {
                          setSheetState(() => type = detected);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Stream URL',
                        helperText: 'm3u8 / mpd / flv / mp4 is detected automatically.',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text(
                        'Advanced options',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Only open this if the source requires headers, ClearKey or WebView.',
                      ),
                      children: [
                        const SizedBox(height: 8),
                        TextField(
                          controller: ref,
                          decoration: const InputDecoration(
                            labelText: 'Referer header',
                            hintText: 'Optional',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: org,
                          decoration: const InputDecoration(
                            labelText: 'Origin header',
                            hintText: 'Optional',
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!web && type == 'dash') ...[
                          TextField(
                            controller: kid,
                            decoration: const InputDecoration(
                              labelText: 'ClearKey keyID',
                              hintText: 'Optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: key,
                            decoration: const InputDecoration(
                              labelText: 'ClearKey keyData',
                              hintText: 'Optional',
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use WebView instead'),
                          value: web,
                          onChanged: (v) =>
                              setSheetState(() => web = v),
                        ),
                        if (web) ...[
                          const SizedBox(height: 6),
                          TextField(
                            controller: webUrl,
                            decoration: const InputDecoration(
                              labelText: 'WebView URL',
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('SAVE CHANGES'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (save != true) return;

    final effectiveType =
        web ? 'auto' : detectStreamType(url.text, fallback: type);

    await Supabase.instance.client
        .from('stream_links')
        .update({
          'label': name.text.trim().isEmpty ? 'Server' : name.text.trim(),
          'resolution': name.text.trim().isEmpty ? 'Server' : name.text.trim(),
          'stream_type': effectiveType,
          'stream_url': web ? '' : url.text.trim(),
          'referer': nullable(ref.text),
          'origin': nullable(org.text),
          'key_id': !web && effectiveType == 'dash' ? nullable(kid.text) : null,
          'key_data': !web && effectiveType == 'dash' ? nullable(key.text) : null,
          'use_webview': web,
          'webview_url': web ? nullable(webUrl.text) : null,
          'send_notification': false,
        })
        .eq('id', row['id']);

    if (mounted) {
      message('Server updated.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Links')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadMatches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final matches = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: matchId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Match',
                          prefixIcon: Icon(Icons.sports_soccer_rounded),
                        ),
                        items: matches
                            .map(
                              (m) => DropdownMenuItem(
                                value: m['id'] as String,
                                child: Text(
                                  '${m['home_team']} vs ${m['away_team']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => matchId = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: serverName,
                        decoration: const InputDecoration(
                          labelText: 'Server name',
                          hintText: 'Main / Backup / Server 1',
                          prefixIcon: Icon(Icons.dns_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: streamType,
                        decoration: const InputDecoration(
                          labelText: 'Stream type',
                          prefixIcon: Icon(Icons.play_circle_outline_rounded),
                        ),
                        items: streamTypes.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: useWebView
                            ? null
                            : (v) => setState(
                                  () => streamType = v ?? 'auto',
                                ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: link,
                        enabled: !useWebView,
                        minLines: 2,
                        maxLines: 4,
                        keyboardType: TextInputType.url,
                        onChanged: (value) {
                          final detected = detectStreamType(value);
                          if (detected != 'auto' && detected != streamType) {
                            setState(() => streamType = detected);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Stream URL',
                          hintText: 'Paste m3u8 / mpd / flv / mp4 / direct URL',
                          helperText: 'Stream type is detected automatically.',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          'Advanced options',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'Leave closed for normal links.',
                        ),
                        children: [
                          const SizedBox(height: 6),
                          TextField(
                            controller: referer,
                            decoration: const InputDecoration(
                              labelText: 'Referer header',
                              hintText: 'Optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: origin,
                            decoration: const InputDecoration(
                              labelText: 'Origin header',
                              hintText: 'Optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!useWebView && streamType == 'dash') ...[
                            TextField(
                              controller: keyId,
                              decoration: const InputDecoration(
                                labelText: 'ClearKey keyID',
                                hintText: 'Optional',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: keyData,
                              decoration: const InputDecoration(
                                labelText: 'ClearKey keyData',
                                hintText: 'Optional',
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Use WebView instead'),
                            value: useWebView,
                            onChanged: (v) =>
                                setState(() => useWebView = v),
                          ),
                          if (useWebView) ...[
                            const SizedBox(height: 6),
                            TextField(
                              controller: webViewUrl,
                              decoration: const InputDecoration(
                                labelText: 'WebView URL',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: loading ? null : addLink,
                          icon: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_link_rounded),
                          label: Text(
                            loading ? 'ADDING...' : 'ADD SERVER',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (matchId != null) ...[
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      'Existing Servers',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadLinks(),
                  builder: (context, linkSnapshot) {
                    if (!linkSnapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final rows = linkSnapshot.data!;
                    if (rows.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            'No servers added yet.',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: rows.map((row) {
                        final name =
                            '${row['label'] ?? row['resolution'] ?? 'Server'}';
                        final type = row['use_webview'] == true
                            ? 'WEBVIEW'
                            : streamTypes[
                                      (row['stream_type'] ?? 'auto').toString()
                                    ] ??
                                'Auto / Direct';
                        final url = row['use_webview'] == true
                            ? '${row['webview_url'] ?? ''}'
                            : '${row['stream_url'] ?? ''}';
                        final active = row['is_active'] == true;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: colors.outlineVariant
                                    .withValues(alpha: .5),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: colors.primary
                                              .withValues(alpha: .1),
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: Icon(
                                          Icons.dns_rounded,
                                          color: colors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              type,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    colors.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => editLink(row),
                                        icon: const Icon(Icons.edit_rounded),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        color: Colors.redAccent,
                                        onPressed: () =>
                                            deleteLink(row['id']),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      url,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  SwitchListTile.adaptive(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Active'),
                                    value: active,
                                    onChanged: (v) =>
                                        setActive(row['id'], v),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
