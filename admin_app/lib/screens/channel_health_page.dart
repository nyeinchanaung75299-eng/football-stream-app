import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/function_gateway.dart';
import '../services/channel_reachability.dart';
import 'channel_reports_page.dart';

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
  bool cancelScan = false;
  int scanChecked = 0;
  int scanTotal = 0;
  int scanErrors = 0;
  late Future<List<Map<String, dynamic>>> rows = _load();

  @override
  void dispose() {
    cancelScan = true;
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
        'id,channel_id,label,stream_type,is_active,health_status,health_latency_ms,health_http_status,last_checked_at');
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

  /// The All control performs an actual scan, not only a database filter.
  /// Limit client concurrency to three channel requests, each using the
  /// authenticated, server-side stream-health probe. Never expose URLs.
  Future<void> _checkAll(List<Map<String, dynamic>> channels) async {
    if (scanningAll || checkingChannel != null) return;
    final targets = channels
        .where((channel) => channel['is_active'] == true && (channel['line_count'] as int) > 0)
        .toList(growable: false);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active channel lines to check.')),
      );
      return;
    }
    setState(() {
      scanningAll = true;
      cancelScan = false;
      scanTotal = targets.length;
      scanChecked = 0;
      scanErrors = 0;
    });
    var index = 0;
    Future<void> worker() async {
      while (!cancelScan && index < targets.length) {
        final channel = targets[index++];
        try {
          await FunctionGateway.invoke(
            'stream-health', body: {'channel_id': channel['id'].toString()},
          ).timeout(const Duration(seconds: 40));
        } catch (_) {
          scanErrors++;
        }
        if (mounted) setState(() => scanChecked++);
      }
    }
    await Future.wait(List.generate(3, (_) => worker()));
    if (!mounted) return;
    setState(() => scanningAll = false);
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Checked $scanChecked of $scanTotal channels'
          '${scanErrors == 0 ? '' : ' • $scanErrors requests failed'}'),
    ));
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
              (selectedStatus == 'all' || c['status'] == selectedStatus);
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
              '${data.length} CHANNELS • ${counts['reachable'] ?? 0} REACHABLE • ${counts['partial'] ?? 0} PARTIAL • ${counts['failed'] ?? 0} FAILED • ${counts['stale'] ?? 0} STALE',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text('Reachable checks the first bytes only; video playback is not verified. Tap a channel for line results.'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 5, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: scanningAll ? null : () => _checkAll(data),
                  icon: const Icon(Icons.fact_check_rounded),
                  label: Text(scanningAll
                      ? 'CHECKING $scanChecked / $scanTotal'
                      : 'CHECK ALL ${data.length} CHANNELS'),
                ),
                if (scanningAll) ...[
                  TextButton(onPressed: () => setState(() => cancelScan = true),
                    child: Text(cancelScan ? 'STOPPING…' : 'STOP CHECKING')),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: scanTotal == 0 ? null : scanChecked / scanTotal,
                    minHeight: 5,
                  ),
                  const SizedBox(height: 4),
                  Text('$scanChecked / $scanTotal checked • $scanErrors request errors',
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
                      '${channel['reachable_lines']}/${channel['line_count']} reachable • ${channel['failed_lines']} failed\n${status.toUpperCase()} • $detail',
                    ),
                    children: [
                      for (final line in (channel['lines'] as List).cast<Map<String, dynamic>>())
                        ListTile(
                          dense: true,
                          title: Text('${line['label'] ?? 'Line'} • ${line['stream_type'] ?? ''}'),
                          subtitle: Text('${assessChannelReachability([line]).status.toUpperCase()} • HTTP ${line['health_http_status'] ?? '—'} • ${line['health_latency_ms'] ?? '—'} ms\n${line['last_checked_at'] == null ? 'Not checked' : DateFormat('dd MMM, h:mm a').format(DateTime.parse(line['last_checked_at'].toString()).toLocal())}'),
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
