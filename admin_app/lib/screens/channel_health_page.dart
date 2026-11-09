import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/function_gateway.dart';
import '../services/channel_reachability.dart';
import 'channel_reports_page.dart';
import 'channel_playback_test_page.dart';
import 'channels_page.dart';

/// Admin-only TV channel diagnostics. Loads reachability metadata without
/// touching private URLs, playback tokens, referers, or DRM credentials.
class ChannelHealthPage extends StatefulWidget {
  const ChannelHealthPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ChannelHealthPage> createState() => _ChannelHealthPageState();
}

class _ChannelHealthPageState extends State<ChannelHealthPage> {
  final search = TextEditingController();
  String selectedStatus = 'all';
  String? checkingChannel;
  bool scanningAll = false;
  Map<String,dynamic> job = const {};
  Timer? jobTimer;
  bool polling = false;
  int scanChecked = 0;
  int scanTotal = 0;
  int scanErrors = 0;
  late Future<List<Map<String, dynamic>>> rows = _load();

  @override
  void initState() { super.initState(); _pollJob(); }

  @override
  void dispose() {
    jobTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final db = Supabase.instance.client;
    Future<List<Map<String, dynamic>>> allRows(String table, String columns) async {
      final result = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 500) {
        final page = await db.from(table).select(columns).order('id')
            .range(offset, offset + 499).timeout(const Duration(seconds: 15));
        result.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 500) return result;
      }
    }
    final channels = await allRows('channels', 'id,name,category,is_active');
    final lines = await allRows('channel_lines',
        'id,channel_id,label,stream_type,is_active,configuration_status,health_status,health_latency_ms,health_http_status,last_checked_at,manifest_status,segment_status,drm_status,playback_status,playback_device,last_playback_checked_at,health_detail,telegram_probe_status,telegram_probe_http_status,telegram_probe_checked_at');
    final byChannel = <String, List<Map<String, dynamic>>>{};
    for (final line in lines) {
      final id = line['channel_id']?.toString() ?? '';
      byChannel.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(line));
    }
    return [
      for (final c in channels)
        _summarize(Map<String, dynamic>.from(c),
            byChannel[c['id']?.toString()] ?? const []),
    ];
  }

  Map<String, dynamic> _summarize(
    Map<String, dynamic> channel,
    List<Map<String, dynamic>> lines,
  ) {
    final result = assessChannelReachability(lines);
    return {
      ...channel,
      'status': result.status,
      'line_count': result.activeLines,
      'latency_ms': result.maxLatencyMs,
      'checked_at': result.checkedAt,
      'reachable_lines': result.reachableLines,
      'failed_lines': result.failedLines,
      'lines': lines.where((line) => line['is_active'] == true).toList(),
    };
  }

  void _refresh() {
    if (mounted) setState(() => rows = _load());
  }

  bool get activeJob => ['running','paused'].contains(job['status']);
  Future<void> _pollJob() async {
    if (polling) return;
    polling=true;
    try {
      final data=await FunctionGateway.invoke('stream-health',body:const {'action':'job_status'});
      if (!mounted) return;
      final next=Map<String,dynamic>.from((data as Map)['job'] as Map? ?? {});
      final changed=next['checked']!=job['checked'];
      setState(() {job=next;scanningAll=job['status']=='running';scanChecked=(job['checked'] as num?)?.toInt() ?? 0;
        scanTotal=(job['total'] as num?)?.toInt() ?? 0;scanErrors=(job['failed'] as num?)?.toInt() ?? 0;});
      if (changed) _refresh();
    } catch (_) { /* Keep the last progress while the gateway reconnects. */ }
    finally {
      polling=false;
      if (mounted && activeJob) {jobTimer?.cancel();jobTimer=Timer(const Duration(seconds:5),_pollJob);}
    }
  }
  Future<void> _jobAction(String action,{String mode='all'}) async {
    try {
      await FunctionGateway.invoke('stream-health',body:{'action':action,'mode':mode,if(job['id']!=null)'job_id':job['id']});
      await _pollJob();
    } catch (_) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not update the scan. Refresh and retry.'))); }
  }

  Future<void> _check(Map<String, dynamic> channel) async {
    if (checkingChannel != null || scanningAll) return;
    final id = channel['id'].toString();
    setState(() => checkingChannel = id);
    try {
      await FunctionGateway.invoke('stream-health', body: {'channel_id': id})
          .timeout(const Duration(seconds: 40));
      _refresh();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Channel health check failed. Please retry.')),
      );
    } finally {
      if (mounted) setState(() => checkingChannel = null);
    }
  }

  Color _statusColor(BuildContext context, String status) => switch (status) {
    'reachable' => Colors.green,
    'stale' => Colors.blueGrey,
    'slow' => Colors.orange,
    'partial' => Colors.orange,
    'failed' => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded ? null : AppBar(title: const Text('All TV Channel Health'), actions: [
      IconButton(tooltip: 'Viewer reports', icon: const Icon(Icons.flag_outlined),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChannelReportsPage()))),
      IconButton(
        tooltip: 'Refresh all health metadata',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('RETRY CHANNEL HEALTH'),
          ));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final counts = <String, int>{};
        for (final c in data) {
          final status = c['status'].toString();
          counts[status] = (counts[status] ?? 0) + 1;
        }
        final filtered = data.where((c) {
          final text = '${c['name']} ${c['category']}'.toLowerCase();
          return text.contains(search.text.trim().toLowerCase()) &&
              (selectedStatus == 'all' || c['status'] == selectedStatus ||
               selectedStatus == 'drm' && (c['lines'] as List).any((line)=>line['configuration_status']=='requires_drm') ||
               selectedStatus == 'verified' && (c['lines'] as List).any((line)=>line['playback_status']=='verified'));
        }).toList();
        return Column(children: [
          if (widget.embedded) Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 0),
            child: Row(children: [
              Expanded(child: Text('Channel Health', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(tooltip: 'Viewer reports', icon: const Icon(Icons.flag_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChannelReportsPage()))),
              IconButton(onPressed: scanningAll ? null : _refresh,
                tooltip: 'Refresh results', icon: const Icon(Icons.refresh_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              '${data.length} CHANNELS • ${counts['reachable'] ?? 0} REACHABLE • ${counts['partial'] ?? 0} PARTIAL • ${counts['failed'] ?? 0} MEDIA CHECK FAILED • ${counts['stale'] ?? 0} STALE',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text('HTTP, manifest and segment checks are separate from video decoding. Test Video verifies frames on this device.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 5, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: activeJob ? null : () => _jobAction('start_job'),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: Text(scanningAll
                      ? 'CHECKING $scanChecked / $scanTotal'
                      : 'CHECK ALL ${data.length} CHANNELS'),
                ),
                if (!activeJob) Wrap(spacing:8,children:[
                  TextButton(onPressed:()=>_jobAction('start_job',mode:'failed'),child:const Text('Recheck Failed')),
                  TextButton(onPressed:()=>_jobAction('start_job',mode:'unverified'),child:const Text('Check Unverified')),
                ]),
                if (activeJob) ...[
                  Row(children:[TextButton(onPressed:()=>_jobAction(scanningAll?'pause_job':'resume_job'),child:Text(scanningAll?'Pause':'Resume')),
                    TextButton(onPressed:()=>_jobAction('cancel_job'),child:const Text('Cancel scan'))]),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: scanTotal == 0 ? null : scanChecked / scanTotal,
                    minHeight: 5,
                  ),
                  const SizedBox(height: 4),
                  Text('$scanChecked / $scanTotal lines checked • $scanErrors failed • Continues when this page is closed',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: Row(children: [
              Expanded(child: TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search TV channels',
                  border: OutlineInputBorder(),
                ),
              )),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: selectedStatus,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'reachable', child: Text('Reachable')),
                DropdownMenuItem(value: 'stale', child: Text('Stale')),
                  DropdownMenuItem(value: 'slow', child: Text('Slow')),
                  DropdownMenuItem(value: 'failed', child: Text('Failed')),
                  DropdownMenuItem(value: 'partial', child: Text('Partial')),
                  DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                  DropdownMenuItem(value: 'drm', child: Text('Needs DRM')),
                  DropdownMenuItem(value: 'verified', child: Text('Video verified')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => selectedStatus = value);
                  // The separate CHECK ALL button starts an explicit scan.
                },
              ),
            ]),
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() => rows = next);
              await next;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final channel = filtered[index];
                final id = channel['id'].toString();
                final status = channel['status'].toString();
                final checked = channel['checked_at'] as DateTime?;
                final detail = checked == null ? 'Not checked'
                    : DateFormat('dd MMM, h:mm a').format(checked.toLocal());
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 3, 12, 3),
                  child: ExpansionTile(
                    leading: Icon(Icons.health_and_safety_rounded,
                      color: _statusColor(context, status)),
                    title: Text(channel['name']?.toString() ?? 'Channel',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${channel['reachable_lines']}/${channel['line_count']} reachable • ${channel['failed_lines']} media check failed\n${status.toUpperCase()} • $detail',
                    ),
                    children: [
                      for (final line in (channel['lines'] as List).cast<Map<String, dynamic>>())
                        ListTile(
                          dense: true,
                          title: Text('${line['label'] ?? 'Line'} • ${line['stream_type'] ?? ''}'
                              '${line['configuration_status'] == 'requires_drm' ? ' • Needs DRM configuration' : ''}'),
                          subtitle: Text(
                            'Link: ${line['is_active'] == true ? 'SAVED' : 'DISABLED'}'
                            ' • HTTP: ${line['last_checked_at'] == null ? 'NOT TESTED' : (line['health_http_status'] == null ? 'NO RESPONSE' : line['health_http_status'])}'
                            '\nMedia check: ${line['health_status'] ?? 'unknown'}'
                            '\nBot HTTP probe: ${line['telegram_probe_status'] ?? 'unknown'}'
                            ' (HTTP ${line['telegram_probe_http_status'] ?? '—'})'
                            '\nManifest: ${line['manifest_status'] ?? 'not_tested'}'
                            ' • Segment: ${line['segment_status'] ?? 'not_tested'}'
                            '\nVideo: ${line['playback_status'] == 'verified' ? 'DECODE VERIFIED' : line['playback_status'] == 'failed' ? 'FAILED ON DEVICE' : 'NOT VERIFIED'}'
                            '${line['playback_device']==null?'':' • ${line['playback_device']}'}'
                            '\n${line['last_checked_at'] == null ? 'HTTP not checked' : DateFormat('dd MMM, h:mm a').format(DateTime.parse(line['last_checked_at'].toString()).toLocal())}'
                            '\nA failed server HTTP probe does not prove device video failed.'
                          ),
                          trailing: IconButton(tooltip:line['configuration_status']=='requires_drm'?'Configure DRM':'Test Video',
                            icon:Icon(line['configuration_status']=='requires_drm'?Icons.settings:Icons.play_circle_outline),
                            onPressed:()async{
                              await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>line['configuration_status']=='requires_drm'
                                ? ChannelsPage(initialQuery:channel['name'].toString())
                                : ChannelPlaybackTestPage(lineId:line['id'].toString(),channelId:id)));
                              _refresh();
                            }),
                        ),
                    ],
                    trailing: OutlinedButton(
                      onPressed: checkingChannel == null && !scanningAll &&
                              (channel['line_count'] as int) > 0
                          ? () => _check(channel) : null,
                      child: checkingChannel == id
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('CHECK'),
                    ),
                  ),
                );
              },
            ),
          )),
        ]);
      },
    ),
  );
}
