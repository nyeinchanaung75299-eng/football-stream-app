import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/system_monitor_service.dart';
import 'diagnostics_page.dart';
import 'monitor_connections_page.dart';

class SystemHealthPage extends StatefulWidget {
  const SystemHealthPage({super.key, required this.active, this.loader});
  final bool active;
  final Future<Map<String, dynamic>> Function()? loader;

  @override
  State<SystemHealthPage> createState() => _SystemHealthPageState();
}

class _SystemHealthPageState extends State<SystemHealthPage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _foreground = true;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(SystemHealthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!widget.active || !_foreground) return;
    _refresh();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (widget.loader ?? SystemMonitorService.load)();
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Monitoring could not load. Check your '
            'Admin session and connection, then refresh.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(bool csv) async {
    if (_data == null) return;
    try {
      await Clipboard.setData(ClipboardData(
          text: csv
              ? SystemMonitorService.reportCsv(_data!)
              : SystemMonitorService.reportJson(_data!)));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(csv ? 'CSV report copied.' : 'Summary copied.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not copy the report.')));
      }
    }
  }

  Future<void> _connect() async {
    await Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: '/admin/monitor-connections'),
        builder: (_) => const MonitorConnectionsPage()));
    if (mounted && widget.active) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final services = _data?['services'] as List? ?? const [];
    return ListView(
      key: const PageStorageKey('system-health'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text('System Health',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('App errors, affected users, stream checks and deployments. '
            'Refreshes every minute while this tab is open.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(_loading ? 'Loading…' : 'Refresh monitor')),
          OutlinedButton.icon(
              onPressed: _connect,
              icon: const Icon(Icons.link),
              label: const Text('Connect services')),
          OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  settings:
                      const RouteSettings(name: '/admin/connection-checks'),
                  builder: (_) => const Scaffold(
                      appBar: _ChecksAppBar(), body: DiagnosticsPage()))),
              icon: const Icon(Icons.network_check),
              label: const Text('Connection checks')),
          if (_data != null)
            PopupMenuButton<bool>(
              tooltip: 'Copy report',
              onSelected: _copy,
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('Copy summary')),
                PopupMenuItem(value: true, child: Text('Copy CSV report')),
              ],
              child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.copy),
                    SizedBox(width: 6),
                    Text('Copy report')
                  ])),
            ),
        ]),
        if (_loading)
          const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator()),
        if (_error != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error! +
                      (_data == null
                          ? ''
                          : ' Previous results below are out of date.')))),
        if (_data != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Report time: ${_time(_data!['generatedAt'])}')),
        for (final raw in services)
          _ServiceCard(service: Map<String, dynamic>.from(raw)),
        if (_data?['streams'] is Map)
          _StreamsCard(data: Map<String, dynamic>.from(_data!['streams'])),
      ],
    );
  }
}

class _ChecksAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChecksAppBar();
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  @override
  Widget build(BuildContext context) =>
      AppBar(title: const Text('Connection checks'));
}

String _time(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Not available'
      : DateFormat('yyyy-MM-dd h:mm:ss a', 'en_US').format(date.toLocal());
}

Future<void> openMonitorLink(String raw, BuildContext context) async {
  final uri = Uri.tryParse(raw);
  const hosts = {
    'github.com',
    'us.posthog.com',
    'eu.posthog.com',
    'dash.cloudflare.com',
    'vercel.com',
    'drive.google.com',
    'posthog.com'
  };
  if (uri == null || uri.scheme != 'https' || !hosts.contains(uri.host)) return;
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the dashboard.')));
  }
}

const _titles = {
  'supabase': 'Database · Supabase',
  'github': 'Builds · GitHub Actions',
  'posthog': 'App errors · PostHog',
  'cloudflare': 'Worker · Cloudflare',
  'vercel': 'Backup backend · Vercel',
  'google-drive': 'Reports · Google Drive'
};
const _metricLabels = {
  'matches': 'Matches',
  'activeLines': 'Active lines',
  'latencyMs': 'Database ms',
  'requests': 'Requests',
  'runtimeErrors': 'Runtime errors',
  'subrequests': 'Subrequests',
  'cpuP50Ms': 'CPU p50 ms',
  'cpuP99Ms': 'CPU p99 ms',
  'wallP50Ms': 'Wall time p50 ms',
  'wallP99Ms': 'Wall time p99 ms'
};
const _eventLabels = {
  r'$exception': 'Captured exceptions',
  'playback line failed': 'Playback line failures',
  'playback buffering': 'Buffering events',
  'admin function failed': 'Admin API failures'
};

String _timingLabel(Map row) => switch (row['event']) {
      'playback started' => 'Video startup',
      'playback buffering ended' => row['phase'] == 'startup'
          ? 'Startup buffering'
          : row['phase'] == 'rebuffer'
              ? 'Buffering during playback'
              : 'Buffering duration',
      'stream sources loaded' => 'Line list loading',
      'admin function completed' => 'Admin request',
      _ => 'Measured duration',
    };

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});
  final Map<String, dynamic> service;

  @override
  Widget build(BuildContext context) {
    final state = service['state']?.toString() ?? 'unavailable';
    final color = state == 'ok'
        ? Colors.green
        : state == 'not_configured'
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Colors.orange;
    final metrics = service['metrics'] as Map? ?? {};
    final events = service['events'] as List? ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                    state == 'ok'
                        ? Icons.check_circle_outline
                        : state == 'not_configured'
                            ? Icons.link_off
                            : Icons.warning_amber,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        _titles[service['id']] ?? service['id'].toString(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17))),
              ]),
              const SizedBox(height: 6),
              Text(state.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(service['detail']?.toString() ??
                  'No monitoring data available.'),
              if (state != 'not_configured')
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'Collected: ${_time(service['collectedAt'])}${service['cached'] == true ? ' · cached' : ''}',
                        style: Theme.of(context).textTheme.bodySmall)),
              if (service['lastKnown'] != null)
                const Text('Previous data exists, but the current read failed. '
                    'Refresh after checking the service connection.'),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 16, runSpacing: 12, children: [
                  for (final e in metrics.entries)
                    _Metric(
                        label: _metricLabels[e.key] ?? e.key.toString(),
                        value: e.value == null ? '—' : e.value.toString()),
                ]),
              ],
              for (final e in events)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                        '${_eventLabels[e['event']] ?? e['event'].toString()}: ${e['count']}${e['event'] == 'playback buffering' ? '' : ' · affected users: ${e['affectedUsers']}'}')),
              if (service['timing'] is Map) ...[
                const SizedBox(height: 10),
                Text(service['timing']['note']?.toString() ?? ''),
                if ((service['timing']['rows'] as List? ?? const []).isNotEmpty)
                  ExpansionTile(
                    key: PageStorageKey('monitor-timing-${service['id']}'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Loading / playback timing'),
                    children: [
                      for (final t in service['timing']['rows'])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_timingLabel(t)),
                          subtitle: Text(
                              '${t['app']} · ${t['platform']} · ${t['samples']} samples\n'
                              'Median: ${t['p50Ms']} ms · p95: ${t['p95Ms']} ms'),
                        ),
                    ],
                  ),
              ],
              for (final r in service['runs'] as List? ?? const [])
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r['workflow'] == 'deploy-web.yml'
                        ? 'Web deployment'
                        : 'APK / iOS build'),
                    subtitle: Text(
                        '${r['state']} · ${r['sha'] ?? ''}\n${_time(r['updatedAt'])}'),
                    trailing: const Icon(Icons.open_in_new, size: 20),
                    onTap: r['url'] == null
                        ? null
                        : () => openMonitorLink(r['url'].toString(), context)),
              for (final r in service['deployments'] as List? ?? const [])
                Text(
                    '${r['state']} · ${_time(r['createdAt'])} · ${r['sha'] ?? ''}'),
              if ((service['breakdown'] as List? ?? const []).isNotEmpty)
                ExpansionTile(
                    key: PageStorageKey('monitor-breakdown-${service['id']}'),
                    tilePadding: EdgeInsets.zero,
                    title: const Text('App / platform breakdown'),
                    children: [
                      for (final b in service['breakdown'])
                        ListTile(
                            title: Text('${b['app']} · ${b['platform']}'),
                            subtitle: Text(
                                '${b['event']}: ${b['count']} · affected users: ${b['affectedUsers']}')),
                    ]),
              for (final (index, issue)
                  in (service['issues'] as List? ?? const []).indexed)
                ExpansionTile(
                    key: PageStorageKey('monitor-issue-${service['id']}-'
                        '${issue['issue']}-${issue['title']}-$index'),
                    tilePadding: EdgeInsets.zero,
                    title: Text(issue['title'].toString()),
                    subtitle: Text(
                        '${issue['count']} events · ${issue['affectedUsers']} affected users'),
                    children: [
                      Text('Last seen: ${_time(issue['lastSeen'])}'),
                      Text('Screen: ${issue['screen'] ?? 'Unknown'}'),
                      SelectableText(
                          issue['stack']?.toString() ?? 'No stack captured.',
                          key: PageStorageKey('monitor-stack-${service['id']}-'
                              '${issue['issue']}-${issue['title']}-$index'),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                      if (issue['url'] != null)
                        TextButton(
                            onPressed: () => openMonitorLink(
                                issue['url'].toString(), context),
                            child: const Text('Open issue and event context')),
                    ]),
              for (final f in service['files'] as List? ?? const [])
                Text('${f['name']} · ${_time(f['modifiedAt'])}'),
              for (final key in ['replay', 'logs'])
                if (service[key] != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(service[key].toString(),
                          style: Theme.of(context).textTheme.bodySmall)),
              if (service['url'] != null)
                TextButton.icon(
                    onPressed: () =>
                        openMonitorLink(service['url'].toString(), context),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(service['id'] == 'google-drive'
                        ? 'Open archive folder'
                        : 'Open service dashboard')),
            ],
          )),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _StreamsCard extends StatelessWidget {
  const _StreamsCard({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Streaming Lines Health',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(data['note']?.toString() ?? ''),
              if (data['truncated'] == true)
                const Text(
                    'This report is limited to 500 lines. Counts below cover that sample.'),
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 10, children: [
                for (final e in (data['counts'] as Map).entries)
                  _Metric(label: e.key.toString(), value: e.value.toString()),
              ]),
              for (final source in data['sources'] as List? ?? const [])
                if (source['allFailing'] == true)
                  Text(
                      'Source warning: ${source['source']} · every listed line has repeated failures.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              for (final line in data['lines'] as List? ?? const [])
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        line['alert'] == true
                            ? Icons.error_outline
                            : line['health'] == 'healthy'
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                        color: line['alert'] == true
                            ? Colors.red
                            : line['health'] == 'healthy'
                                ? Colors.green
                                : Colors.orange),
                    title: Text('${line['label']} · ${line['type']}'),
                    subtitle: Text(
                        '${line['health']} · consecutive failures: ${line['consecutiveFailures']}\n${line['match']}\nChecked: ${_time(line['checkedAt'])}')),
            ],
          )));
}
