import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../analytics_service.dart';
import '../services/function_gateway.dart';
import '../services/admin_match_rules.dart';
import '../widgets/stream_links_list.dart';
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
  final Set<String> checkingLinks = <String>{};
  bool testingHealth = false;
  late Future<List<Map<String, dynamic>>> _matchesFuture;
  Future<List<Map<String, dynamic>>>? _linksFuture;

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
    _matchesFuture = loadMatches();
    if (matchId != null) {
      _linksFuture = loadLinks();
    }
  }

  void reloadLinks() {
    if (!mounted || matchId == null) return;
    setState(() => _linksFuture = loadLinks());
  }

  void selectMatch(String? value) {
    setState(() {
      matchId = value;
      _linksFuture = value == null ? null : loadLinks();
    });
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
            'The protected Viewer now proxies non-DRM DASH/MPD as well as HLS. '
            'ClearKey/keyed DASH is still kept private; add an authorized HLS/FairPlay-compatible backup for iPhone when needed. '
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
              (row['id'] == matchId ||
                  (row['is_active'] == true &&
                      row['is_finished'] != true &&
                      row['is_featured'] != false &&
                      (row['publish_state'] ?? 'published') == 'published' &&
                      !stale));
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

    final urlError = activeStreamUrlError(
      isActive: true,
      useWebView: useWebView,
      streamUrl: link.text,
      webViewUrl: webViewUrl.text,
    );
    if (urlError != null) {
      message(urlError);
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
      reloadLinks();
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

  Future<void> testHealth() async {
    if (matchId == null) {
      message('Select a match first.');
      return;
    }

    setState(() => testingHealth = true);
    try {
      final data = await FunctionGateway.invoke(
        'stream-health',
        body: {'match_id': matchId},
      );
      await AnalyticsService.capture(
        'stream health checked',
        properties: {
          'scope': 'match',
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
      } else {
        message('Health check finished.');
      }

      reloadLinks();
    } catch (e) {
      await AnalyticsService.capture(
        'stream health check failed',
        properties: {'scope': 'match'},
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
        reloadLinks();
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

    reloadLinks();
  }

  Future<void> checkHealth(String id) async {
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

      if (mounted) {
        reloadLinks();
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
      if (mounted) message('Health check failed: $e');
    } finally {
      if (mounted) {
        setState(() => checkingLinks.remove(id));
      }
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
    String? urlError;

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
                    if (urlError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        urlError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          final error = activeStreamUrlError(
                            isActive: row['is_active'] == true,
                            useWebView: web,
                            streamUrl: url.text,
                            webViewUrl: webUrl.text,
                          );
                          if (error != null) {
                            setSheetState(() => urlError = error);
                            return;
                          }
                          Navigator.pop(sheetContext, true);
                        },
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

    if (!web && url.text.trim().isEmpty) {
      message('Paste a stream URL before saving an active server.');
      return;
    }
    if (web && webUrl.text.trim().isEmpty) {
      message('Paste a WebView URL before saving an active server.');
      return;
    }

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
        reloadLinks();
      }
    } catch (e) {
      await AnalyticsService.capture('stream update failed');
      if (mounted) message('Server update failed: $e');
    }
  }

  Widget _serverCard(
    Map<String, dynamic> row,
    ColorScheme colors,
  ) {
    final name = '${row['label'] ?? row['resolution'] ?? 'Server'}';
    final streamKey = (row['stream_type'] ?? 'auto').toString();
    final type = row['use_webview'] == true
        ? 'WEBVIEW'
        : streamTypes[streamKey] ?? 'Auto / Direct';
    final url = row['use_webview'] == true
        ? '${row['webview_url'] ?? ''}'
        : '${row['stream_url'] ?? ''}';
    final active = row['is_active'] == true;
    final health = (row['health_status'] ?? 'unknown').toString();
    final latency = (row['health_latency_ms'] as num?)?.toInt();
    final checking = checkingLinks.contains(row['id'].toString());
    final keyedDash =
        streamKey == 'dash' &&
        ((row['key_id']?.toString().trim().isNotEmpty ?? false) ||
            (row['key_data']?.toString().trim().isNotEmpty ?? false));

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      keyedDash ? Icons.lock_rounded : Icons.dns_rounded,
                      color: keyedDash ? colors.error : colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                type,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _HealthChip(
                              status: health,
                              latencyMs: latency,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Server actions',
                    onSelected: (value) {
                      if (value == 'edit') {
                        editLink(row);
                      } else if (value == 'delete') {
                        deleteLink(row['id'].toString());
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.edit_rounded),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (keyedDash) ...[
                const SizedBox(height: 9),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.errorContainer.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'KEYED DASH • Viewer shows this as blocked. '
                    'Use HLS or non-DRM DASH for public playback.',
                    style: TextStyle(
                      color: colors.onErrorContainer,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (url.trim().isNotEmpty) ...[
                const SizedBox(height: 9),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: checking
                          ? null
                          : () => checkHealth(row['id'].toString()),
                      icon: checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.monitor_heart_rounded, size: 18),
                      label: Text(checking ? 'CHECKING' : 'CHECK'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Active',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  Switch.adaptive(
                    value: active,
                    onChanged: (value) =>
                        setActive(row['id'].toString(), value),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Live Links')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _matchesFuture,
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
                        onChanged: selectMatch,
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
                                  reloadLinks();
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
                      onPressed: () {
                        setState(() {
                          _matchesFuture = loadMatches();
                          _linksFuture = loadLinks();
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamLinksList(
                  key: ValueKey(matchId),
                  future: _linksFuture ??= loadLinks(),
                  rowBuilder: (row) => _serverCard(row, colors),
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
