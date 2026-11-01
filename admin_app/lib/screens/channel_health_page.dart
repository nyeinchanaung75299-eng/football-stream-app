import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/function_gateway.dart';

/// Admin-only TV channel diagnostics. Loads reachability metadata without
/// touching private URLs, playback tokens, referers, or DRM credentials.
class ChannelHealthPage extends StatefulWidget {
  const ChannelHealthPage({super.key});
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
    final channels = await db
        .from('channels')
        .select('id,name,category,is_active')
        .order('name')
        .limit(1000)
        .timeout(const Duration(seconds: 15));
    final lines = await db
        .from('channel_lines')
        .select('channel_id,is_active,health_status,health_latency_ms,last_checked_at')
        .limit(2000)
        .timeout(const Duration(seconds: 15));
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
    final active = lines.where((line) => line['is_active'] == true).toList();
    final statuses = active.map((line) => (line['health_status'] ?? 'unknown').toString()).toList();
    final status = statuses.isEmpty ? 'unknown'
        : statuses.contains('failed') ? 'failed'
        : statuses.contains('slow') ? 'slow'
        : statuses.every((value) => value == 'healthy') ? 'healthy'
        : 'unknown';
    final latencies = active
        .map((line) => line['health_latency_ms'])
        .whereType<num>()
        .map((value) => value.toInt())
        .where((value) => value > 0)
        .toList();
    final checked = active
        .map((line) => DateTime.tryParse(line['last_checked_at']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList()..sort((a, b) => b.compareTo(a));
    return {
      ...channel,
      'status': status,
      'line_count': active.length,
      'latency_ms': latencies.isEmpty ? null : latencies.reduce((a, b) => a > b ? a : b),
      'checked_at': checked.isNotEmpty ? checked.first : null,
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
        .where((channel) => (channel['line_count'] as int) > 0)
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
    'healthy' => Colors.green,
    'slow' => Colors.orange,
    'failed' => Theme.of(context).colorScheme.error,
    _ => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('All TV Channel Health'), actions: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              '${data.length} CHANNELS  •  ${counts['healthy'] ?? 0} HEALTHY  •  ${counts['slow'] ?? 0} SLOW  •  ${counts['failed'] ?? 0} FAILED  •  ${counts['unknown'] ?? 0} UNKNOWN',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text('All runs a bounded check of every active TV channel. Healthy means the first stream bytes were reachable, not confirmed playback.'),
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
                  DropdownMenuItem(value: 'healthy', child: Text('Healthy')),
                  DropdownMenuItem(value: 'slow', child: Text('Slow')),
                  DropdownMenuItem(value: 'failed', child: Text('Failed')),
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
                  child: ListTile(
                    leading: Icon(Icons.health_and_safety_rounded,
                      color: _statusColor(context, status)),
                    title: Text(channel['name']?.toString() ?? 'Channel',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${channel['category']} • ${channel['line_count']} active lines\n${status.toUpperCase()} • $detail • ${channel['latency_ms'] == null ? 'No latency yet' : '${channel['latency_ms']} ms'}',
                      maxLines: 2,
                    ),
                    isThreeLine: true,
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
