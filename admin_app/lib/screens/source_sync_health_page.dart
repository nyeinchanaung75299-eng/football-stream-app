import 'package:flutter/material.dart';

import '../services/connected_channel_source.dart';
import '../services/highlights_service.dart';

/// Read-only diagnostics. A failed source is *unknown*, never "zero matches".
class SourceSyncHealthPage extends StatefulWidget {
  const SourceSyncHealthPage({super.key, this.loader});

  /// Injectable for widget tests; sources are darkbyte, repository,
  /// repository-imports and highlights.
  final Future<Map<String, dynamic>> Function(String source)? loader;

  @override
  State<SourceSyncHealthPage> createState() => _SourceSyncHealthPageState();
}

class _SourceSyncHealthPageState extends State<SourceSyncHealthPage> {
  static const sources = <String, String>{
    'darkbyte': 'Stream Hub',
    'repository': 'Repository Match / Live 2',
    'repository-imports': 'Repository Link Updates',
    'highlights': 'Admin HL · DasFootball',
  };
  List<Map<String, dynamic>> _states = const [];
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Map<String, dynamic>> _fetch(String source) async {
    if (widget.loader != null) return widget.loader!(source);
    if (source == 'highlights') {
      return const HighlightsService().request('catalog', {'offset': 0});
    }
    return ConnectedChannelSource(source: source).request('state');
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    final states = await Future.wait(sources.keys.map((source) async {
      try {
        final response = await _fetch(source);
        if (source == 'highlights') {
          return <String, dynamic>{
            'id': source,
            'status': response['unavailable'] == true
                ? 'unavailable'
                : response['stale'] == true
                    ? 'partial'
                    : 'ok',
            'entry_count': response['total'],
            'last_checked_at': response['updated_at'],
            'detail': response['unavailable'] == true
                ? 'Provider unavailable. Existing highlights are not deleted.'
                : response['stale'] == true
                    ? 'Showing cached highlights; refresh did not verify changes.'
                    : 'Count covers the returned source page, not all highlights.',
          };
        }
        final state = response['state'];
        if (state is! Map) throw const FormatException('Missing source state');
        return <String, dynamic>{'id': source, ...Map<String, dynamic>.from(state)};
      } catch (_) {
        return <String, dynamic>{
          'id': source,
          'status': 'unknown',
          'detail': 'Could not verify this source. No deletion is inferred.',
        };
      }
    }));
    if (!mounted || generation != _generation) return;
    setState(() {
      _states = states;
      _loading = false;
    });
  }

  String _time(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Not confirmed';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Source Sync Health')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Read-only source health. Partial or unavailable is not proof '
              'that an upstream match or stream link was deleted.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(_loading ? 'Checking sources…' : 'Refresh source status'),
            ),
            if (_loading) const LinearProgressIndicator(),
            for (final state in _states) _sourceCard(state),
          ],
        ),
      ),
    );
  }

  Widget _sourceCard(Map<String, dynamic> state) {
    final name = sources[state['id']] ?? state['id'].toString();
    final status = (state['status'] ?? 'unknown').toString();
    final healthy = status == 'ok';
    final warning = status == 'partial' || status == 'unavailable';
    final color = healthy
        ? Colors.green
        : warning
            ? Colors.orange
            : Theme.of(context).colorScheme.onSurfaceVariant;
    final missing = (state['unavailable_repositories'] as List? ?? const [])
        .whereType<String>().toList();
    final count = state['entry_count'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(healthy ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
          Text(status.toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          if (count != null) Text('Source entries: $count'),
          Text('Last checked: ${_time(state['last_checked_at'])}'),
          if (state['id'] != 'highlights')
            Text('Last confirmed sync: ${_time(state['last_success_at'])}'),
          if (missing.isNotEmpty)
            Text('Unverified repositories: ${missing.join(', ')}'),
          if (state['detail'] != null) Text(state['detail'].toString()),
        ]),
      ),
    );
  }
}
