import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/highlights_service.dart';

/// Session-scoped, lazy direct-link catalogue. No media is downloaded until
/// the Admin explicitly requests a first-byte link check.
class HighlightsPage extends StatefulWidget {
  const HighlightsPage({super.key, this.service = const HighlightsService()});
  final HighlightsService service;

  @override
  State<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends State<HighlightsPage> {
  final _search = TextEditingController();
  Map<String, dynamic>? _data;
  Future<void>? _inFlight;
  DateTime? _loadedAt;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!force && _loadedAt != null && DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    final operation = _fetch(force);
    _inFlight = operation;
    operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
      if (mounted) setState(() {});
    });
    return operation;
  }

  Future<void> _fetch(bool force) async {
    try {
      final data = await widget.service.request('catalog', {'force': force});
      if (!mounted) return;
      setState(() {
        _error = null;
        if (data['unavailable'] != true || _data == null) _data = data;
        if (data['unavailable'] == true) {
          _error = (data['warnings'] as List? ?? ['Could not extract highlight links.']).join(' ');
        } else if (data['stale'] != true) {
          _loadedAt = DateTime.now();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not refresh. Showing the last successful links, if available.');
    }
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _notice('Copied.');
    } catch (_) { _notice('Copy failed. Select and copy the URL shown in the details.'); }
  }

  Future<void> _details(Map<String, dynamic> row) async {
    if (_opening) return;
    setState(() => _opening = true);
    Map<String, dynamic> entry;
    try {
      final result = await widget.service.request('details', {'entry_id': row['id']});
      entry = Map<String, dynamic>.from(result['entry'] as Map);
    } catch (_) {
      _notice('Could not refresh these links. Showing links already extracted from the list.');
      entry = row;
    } finally { if (mounted) setState(() => _opening = false); }
    if (!mounted) return;
    final lines = highlightMaps(entry['lines']);
    final checks = <String, String>{};
    final checking = <String>{};
    await showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, useSafeArea: true,
      builder: (sheet) => StatefulBuilder(builder: (_, update) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .85),
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry['title']?.toString() ?? 'Highlights', style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${lines.length} extracted links • DasFootball'),
            for (final line in lines) Card(margin: const EdgeInsets.only(top: 12), child: Padding(
              padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${line['label']} • ${line['stream_type'].toString().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(line['stream_url'].toString(), maxLines: 4),
                for (final field in ['referer', 'origin', 'user_agent'])
                  if (line[field] != null) SelectableText('$field: ${line[field]}', style: const TextStyle(fontSize: 12), maxLines: 2),
                const SizedBox(height: 8),
                Text(checks[line['id']] ?? 'Link not checked', style: const TextStyle(fontSize: 12)),
                Wrap(spacing: 6, children: [
                  TextButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('Copy URL'),
                    onPressed: () => _copy(line['stream_url'].toString())),
                  TextButton.icon(icon: const Icon(Icons.content_paste, size: 18), label: const Text('Copy details'),
                    onPressed: () => _copy(highlightCopyDetails(line))),
                  TextButton.icon(icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(checking.contains(line['id']) ? 'Checking…' : 'Check link'),
                    onPressed: checking.contains(line['id']) ? null : () async {
                      final id = line['id'].toString();
                      update(() => checking.add(id));
                      try {
                        final response = await widget.service.request('check', {'entry_id': entry['id'], 'line_id': id});
                        final check = response['check'] as Map;
                        if (sheet.mounted) update(() => checks[id] = '${check['status'] == 'reachable' ? 'Link reachable' : 'Failed / invalid link'} • HTTP ${check['http']} • ${check['ms']} ms');
                      } catch (_) {
                        if (sheet.mounted) update(() => checks[id] = 'Check failed. Refresh the list if this link changed.');
                      } finally { if (sheet.mounted) update(() => checking.remove(id)); }
                    }),
                ]),
              ]),
            )),
            if (lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No direct HLS / MP4 link was extracted. Refresh the list.')),
          ]),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _inFlight != null;
    final rows = highlightMaps(_data?['entries']).where((row) =>
      highlightMaps(row['lines']).isNotEmpty && highlightMatchesQuery(row, _search.text)).toList();
    final warnings = (_data?['warnings'] as List? ?? []).map((value) => value.toString()).toSet();
    if (_error != null) warnings.add(_error!);
    final updated = DateTime.tryParse(_data?['updated_at']?.toString() ?? '')?.toLocal();
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights'), actions: [
        IconButton(tooltip: 'Refresh highlights', onPressed: loading ? null : () {
          _load(force: true); setState(() {});
        }, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: TextField(controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: 'Search teams or highlights', prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close),
              onPressed: () => setState(() => _search.clear()))))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Align(alignment: Alignment.centerLeft,
          child: Text('DasFootball • ${rows.length} highlights${updated == null ? '' : ' • ${DateFormat('dd MMM, h:mm a').format(updated)}'}', style: const TextStyle(fontSize: 12)))),
        if (loading || _opening) const LinearProgressIndicator(),
        if (warnings.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text(warnings.join(' '), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: loading ? null : () { _load(force: true); setState(() {}); }, child: const Text('Retry')),
        ])),
        Expanded(child: RefreshIndicator(onRefresh: () => _load(force: true), child: ListView.builder(
          key: const PageStorageKey('highlights-dasfootball'), padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          itemCount: rows.isEmpty ? 1 : rows.length,
          itemBuilder: (context, index) {
            if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Text(
              loading ? 'Extracting highlight links…' : 'No extracted links to show. Refresh or clear your search.'));
            final row = rows[index]; final count = highlightMaps(row['lines']).length;
            final published = DateTime.tryParse(row['published_at']?.toString() ?? '')?.toLocal();
            return Card(child: ListTile(contentPadding: const EdgeInsets.all(12),
              leading: row['thumbnail_url'] == null ? const Icon(Icons.link) :
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(row['thumbnail_url'].toString(),
                  width: 64, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 48, child: Icon(Icons.link)))),
              title: Text(row['title']?.toString() ?? 'Highlights', maxLines: 3),
              subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                'Get links • $count extracted${published == null ? '' : '\n${DateFormat('dd MMM, h:mm a').format(published)}'}')),
              trailing: const Icon(Icons.chevron_right), onTap: _opening ? null : () => _details(row)));
          },
        ))),
      ]),
    );
  }
}
