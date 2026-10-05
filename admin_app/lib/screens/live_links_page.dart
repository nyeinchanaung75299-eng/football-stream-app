import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../analytics_service.dart';
import '../services/function_gateway.dart';
import 'soco_import_page.dart';

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
  bool checkingAll = false;
  final Set<String> checkingLinks = <String>{};
  bool testingHealth = false;

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

  Widget _dashCompatibilityNotice(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'The protected Viewer currently excludes DASH and ClearKey lines. '
            'For iPhone playback, add a compatible HLS backup to this same match. '
            'HTTP health checks report reachability only.',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,home_team,away_team,league,kickoff_at,sort_order,is_live,is_active,'
          'is_finished,is_featured,publish_state,deleted_at',
        )
        .order('kickoff_at', ascending: true)
        .order('sort_order', ascending: true)
        .order('home_team', ascending: true);

    final now = DateTime.now();
    const staleKickoffGrace = Duration(hours: 5);

    return List<Map<String, dynamic>>.from(data)
        .where((row) {
          final kickoff = DateTime.tryParse(
            row['kickoff_at']?.toString() ?? '',
          )?.toLocal();
          final stale = row['is_live'] != true &&
              kickoff != null &&
              now.difference(kickoff) > staleKickoffGrace;

          return row['deleted_at'] == null &&
              row['is_active'] == true &&
              row['is_finished'] != true &&
              row['is_featured'] != false &&
              (row['publish_state'] ?? 'published') == 'published' &&
              !stale;
        })
        .toList();
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

      await AnalyticsService.capture(
        'stream added',
        properties: {
          'match_id': matchId!,
          'stream_type': effectiveType,
          'use_webview': useWebView,
          'has_referer': referer.text.trim().isNotEmpty,
          'has_origin': origin.text.trim().isNotEmpty,
          'has_clearkey':
              keyId.text.trim().isNotEmpty && keyData.text.trim().isNotEmpty,
        },
      );

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
      await AnalyticsService.capture(
        'stream add failed',
        properties: {
          'match_selected': matchId != null,
          'use_webview': useWebView,
        },
      );
      if (!mounted) return;
      message(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> testHealth({String? linkId}) async {
    if (linkId == null && matchId == null) {
      message('Select a match first.');
      return;
    }

    setState(() => testingHealth = true);
    try {
      final body = <String, dynamic>{};
      if (linkId != null) {
        body['link_id'] = linkId;
      } else {
        body['match_id'] = matchId;
      }

      final data = await FunctionGateway.invoke(
        'stream-health',
        body: body,
      );
      await AnalyticsService.capture(
        'stream health checked',
        properties: {
          'scope': linkId != null ? 'link' : 'match',
          if (data is Map && data['health_status'] != null)
            'health_status': data['health_status'].toString(),
        },
      );
      if (!mounted) return;

      if (data is Map && data['summary'] is Map) {
        final summary = Map<String, dynamic>.from(data['summary'] as Map);
        message(
          'Health: ${summary['healthy'] ?? 0} healthy, '
          '${summary['slow'] ?? 0} slow, '
          '${summary['failed'] ?? 0} failed.',
        );
      } else if (data is Map && data['health_status'] != null) {
        message(
          'Server: ${data['health_status']} '
          '(${data['latency_ms'] ?? '-'} ms)',
        );
      } else {
        message('Health check finished.');
      }

      setState(() {});
    } catch (e) {
      await AnalyticsService.capture(
        'stream health check failed',
        properties: {'scope': linkId != null ? 'link' : 'match'},
      );
      if (mounted) message('Health check failed: $e');
    } finally {
      if (mounted) setState(() => testingHealth = false);
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

    try {
      await Supabase.instance.client
          .from('stream_links')
          .delete()
          .eq('id', id);

      await AnalyticsService.capture(
        'stream deleted',
        properties: {'match_selected': matchId != null},
      );

      if (mounted) {
        message('Server deleted.');
        setState(() {});
      }
    } catch (e) {
      await AnalyticsService.capture('stream delete failed');
      if (mounted) message('Delete failed: $e');
    }
  }

  Future<void> setActive(String id, bool value) async {
    await Supabase.instance.client
        .from('stream_links')
        .update({'is_active': value})
        .eq('id', id);

    await AnalyticsService.capture(
      'stream active changed',
      properties: {'is_active': value},
    );

    if (mounted) setState(() {});
  }

  Future<void> checkHealth(String id, {bool quiet = false}) async {
    if (checkingLinks.contains(id)) return;

    setState(() => checkingLinks.add(id));
    try {
      final data = await FunctionGateway.invoke(
        'stream-health',
        body: {'link_id': id},
      );

      await AnalyticsService.capture(
        'stream health checked',
        properties: {
          'scope': 'link',
          if (data is Map && data['health_status'] != null)
            'health_status': data['health_status'].toString(),
        },
      );

      if (!quiet && mounted) {
        if (data is Map) {
          final status = data['health_status'] ?? 'unknown';
          final latency = data['latency_ms'];
          message(
            latency == null
                ? 'Health: $status'
                : 'Health: $status • ${latency}ms',
          );
        }
      }
    } catch (e) {
      await AnalyticsService.capture(
        'stream health check failed',
        properties: {'scope': 'link'},
      );
      if (!quiet && mounted) message('Health check failed: $e');
    } finally {
      if (mounted) {
        setState(() => checkingLinks.remove(id));
      }
    }
  }

  Future<void> checkAllHealth(List<Map<String, dynamic>> rows) async {
    if (checkingAll) return;
    setState(() => checkingAll = true);

    try {
      final activeRows =
          rows.where((item) => item['is_active'] == true).toList();
      for (final row in activeRows) {
        await checkHealth(row['id'].toString(), quiet: true);
      }
      await AnalyticsService.capture(
        'stream health batch completed',
        properties: {'link_count': activeRows.length},
      );
      if (mounted) message('Health check finished.');
    } finally {
      if (mounted) setState(() => checkingAll = false);
    }
  }

  Color healthColor(String status) {
    switch (status) {
      case 'healthy':
        return Colors.green;
      case 'slow':
        return Colors.orange;
      case 'failed':
        return Colors.redAccent;
      default:
        return Colors.blueGrey;
    }
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
                    if (!web && type == 'dash') ...[
                      const SizedBox(height: 12),
                      _dashCompatibilityNotice(context),
                    ],
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

    try {
      await Supabase.instance.client
          .from('stream_links')
          .update({
            'label': name.text.trim().isEmpty ? 'Server' : name.text.trim(),
            'resolution':
                name.text.trim().isEmpty ? 'Server' : name.text.trim(),
            'stream_type': effectiveType,
            'stream_url': web ? '' : url.text.trim(),
            'referer': nullable(ref.text),
            'origin': nullable(org.text),
            'key_id':
                !web && effectiveType == 'dash' ? nullable(kid.text) : null,
            'key_data':
                !web && effectiveType == 'dash' ? nullable(key.text) : null,
            'use_webview': web,
            'webview_url': web ? nullable(webUrl.text) : null,
            'send_notification': false,
          })
          .eq('id', row['id']);

      await AnalyticsService.capture(
        'stream updated',
        properties: {
          'stream_type': effectiveType,
          'use_webview': web,
          'has_referer': ref.text.trim().isNotEmpty,
          'has_origin': org.text.trim().isNotEmpty,
          'has_clearkey':
              kid.text.trim().isNotEmpty && key.text.trim().isNotEmpty,
        },
      );

      if (mounted) {
        message('Server updated.');
        setState(() {});
      }
    } catch (e) {
      await AnalyticsService.capture('stream update failed');
      if (mounted) message('Server update failed: $e');
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
                          labelText: 'Match • earliest first',
                          prefixIcon: Icon(Icons.schedule_rounded),
                        ),
                        items: matches
                            .map(
                              (m) {
                                final rawKickoff =
                                    m['kickoff_at']?.toString() ?? '';
                                final kickoff =
                                    DateTime.tryParse(rawKickoff)?.toLocal();
                                final when = kickoff == null
                                    ? '--:--'
                                    : DateFormat('dd MMM • HH:mm')
                                        .format(kickoff);
                                return DropdownMenuItem(
                                  value: m['id'] as String,
                                  child: Text(
                                    '$when  ·  ${m['home_team']} vs ${m['away_team']}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            )
                            .toList(),
                        onChanged: (v) => setState(() => matchId = v),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: matchId == null
                              ? null
                              : () async {
                                  await AnalyticsService.capture(
                                    'admin section opened',
                                    properties: {
                                      'section': 'stream-source-picker',
                                      'from': 'stream-servers',
                                    },
                                  );
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      settings: const RouteSettings(
                                        name: '/admin/stream-source-picker',
                                      ),
                                      builder: (_) => SocoImportPage(
                                        initialMatchId: matchId,
                                      ),
                                    ),
                                  );
                                  if (mounted) setState(() {});
                                },
                          icon: const Icon(Icons.podcasts_rounded),
                          label: const Text('PICK STREAM SOURCE'),
                        ),
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
                      if (!useWebView && streamType == 'dash') ...[
                        const SizedBox(height: 12),
                        _dashCompatibilityNotice(context),
                      ],
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
                    OutlinedButton.icon(
                      onPressed: testingHealth ? null : () => testHealth(),
                      icon: testingHealth
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.monitor_heart_rounded),
                      label: const Text('TEST ALL'),
                    ),
                    const SizedBox(width: 6),
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
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: checkingAll
                                ? null
                                : () => checkAllHealth(rows),
                            icon: checkingAll
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.health_and_safety_rounded),
                            label: Text(
                              checkingAll ? 'CHECKING...' : 'CHECK ALL HEALTH',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...rows.map((row) {
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
                        final health =
                            (row['health_status'] ?? 'unknown').toString();
                        final latency =
                            (row['health_latency_ms'] as num?)?.toInt();
                        final checking =
                            checkingLinks.contains(row['id'].toString());

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
                                        tooltip: 'Test server',
                                        onPressed: testingHealth
                                            ? null
                                            : () => testHealth(
                                                  linkId:
                                                      row['id'].toString(),
                                                ),
                                        icon: const Icon(
                                          Icons.monitor_heart_rounded,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: healthColor(health)
                                              .withValues(alpha: .1),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          latency == null
                                              ? health.toUpperCase()
                                              : '${health.toUpperCase()} • ${latency}ms',
                                          style: TextStyle(
                                            color: healthColor(health),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Check health now',
                                        onPressed: checking
                                            ? null
                                            : () => checkHealth(
                                                  row['id'].toString(),
                                                ),
                                        icon: checking
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.monitor_heart_rounded,
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
                                    child: _HealthChip(
                                      status: health,
                                      latencyMs: latency,
                                    ),
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
                        }),
                      ],
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


class _HealthChip extends StatelessWidget {
  const _HealthChip({
    required this.status,
    required this.latencyMs,
  });

  final String status;
  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'healthy' => Colors.green,
      'slow' => Colors.orange,
      'failed' => Colors.redAccent,
      _ => Colors.blueGrey,
    };

    final label = normalized == 'unknown'
        ? 'UNKNOWN'
        : normalized.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        latencyMs == null ? label : '$label • ${latencyMs}ms',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
