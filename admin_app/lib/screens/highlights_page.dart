import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/highlights_service.dart';
import '../services/stream_detector_service.dart';
import 'stream_preview_page.dart';

/// Mounted lazily by the authenticated dashboard; retained until logout.
/// No source/video request is made by another tab or by scrolling thumbnails.
class HighlightsPage extends StatefulWidget {
  const HighlightsPage({super.key, this.service = const HighlightsService()});
  final HighlightsService service;

  @override
  State<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends State<HighlightsPage> {
  final _search = TextEditingController();
  final Map<String, Map<String, dynamic>> _snapshots = {};
  final Map<String, Future<void>> _inFlight = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _queries = {};
  final Map<String, DateTime> _loadedAt = {};
  HighlightsProvider _provider = HighlightsProvider.all.first;
  bool _nativeOnly = false;

  @override
  void initState() {
    super.initState();
    _load(_provider);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(HighlightsProvider provider, {bool force = false}) {
    final existing = _inFlight[provider.id];
    if (existing != null) return existing;
    final loadedAt = _loadedAt[provider.id];
    if (!force && loadedAt != null && DateTime.now().difference(loadedAt) < const Duration(minutes: 5)) {
      return Future.value();
    }
    if (provider.websiteOnly) return Future.value();
    final operation = _fetch(provider, force);
    _inFlight[provider.id] = operation;
    operation.whenComplete(() {
      if (identical(_inFlight[provider.id], operation)) _inFlight.remove(provider.id);
      if (mounted) setState(() {});
    });
    return operation;
  }

  Future<void> _fetch(HighlightsProvider provider, bool force) async {
    try {
      final data = await widget.service.request(provider.id, 'catalog', {'force': force});
      if (!mounted) return;
      setState(() {
        _errors.remove(provider.id);
        // An unavailable response cannot erase the last successful list.
        if (data['unavailable'] != true || !_snapshots.containsKey(provider.id)) {
          _snapshots[provider.id] = data;
        }
        if (data['unavailable'] == true) {
          _errors[provider.id] = (data['warnings'] as List? ?? ['Source unavailable']).join(' ');
        } else if (data['stale'] != true) {
          _loadedAt[provider.id] = DateTime.now();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _errors[provider.id] = 'Could not refresh. Showing the last successful data, if available.');
    }
  }

  void _select(HighlightsProvider provider) {
    if (_provider.id == provider.id) return;
    _queries[_provider.id] = _search.text;
    setState(() {
      _provider = provider;
      _search.text = _queries[provider.id] ?? '';
    });
    _load(provider);
    setState(() {});
  }

  void _notice(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String? raw) async {
    final uri = Uri.tryParse(raw ?? '');
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank')) {
        _notice('Could not open this source. Copy its link and try your browser.');
      }
    } catch (_) { _notice('Could not open this source.'); }
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _notice('Copied.');
    } catch (_) { _notice('Copy failed. Select and copy the URL shown in the details.'); }
  }

  Future<void> _preview(Map<String, dynamic> row, Map<String, dynamic> line) async {
    if (kIsWeb) {
      // The player bundle is downloaded only after this explicit action.
      final uri = Uri.base.resolve('highlight_player.html').replace(fragment: Uri(queryParameters: {
        'url': line['stream_url'].toString(), 'title': row['title'].toString(),
        if (row['source_page_url'] != null) 'source': row['source_page_url'].toString(),
      }).query);
      try {
        if (!await launchUrl(uri, webOnlyWindowName: '_blank')) _notice('Could not open preview.');
      } catch (_) { _notice('Could not open preview.'); }
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => StreamPreviewPage(
      stream: DetectedStream(url: line['stream_url'].toString(), type: line['stream_type'].toString(),
        referer: line['referer']?.toString() ?? '', origin: line['origin']?.toString() ?? ''),
    )));
  }

  Future<void> _details(Map<String, dynamic> row) async {
    final provider = _provider;
    var entry = row;
    if (provider.id == 'hoofoot' || (row['lines'] as List? ?? []).isEmpty) {
      if (provider.websiteOnly) { await _open(provider.url); return; }
      try {
        _notice('Loading highlight links…');
        final result = await widget.service.request(provider.id, 'details', {'entry_id': row['id']});
        entry = Map<String, dynamic>.from(result['entry'] as Map);
      } catch (_) {
        if (!mounted) return;
        _notice('Could not resolve links. You can still open the original website.');
      }
    }
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
            Text('${lines.length} unique video links • ${provider.name}'),
            const SizedBox(height: 8),
            const Text('Reachable checks the media response only. Use Preview to test playback.', style: TextStyle(fontSize: 12)),
            if (entry['detail_warning'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(entry['detail_warning'].toString())),
            for (final line in lines) Card(margin: const EdgeInsets.only(top: 12), child: Padding(
              padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${line['label']} • ${line['stream_type'].toString().toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(line['stream_url'].toString(), maxLines: 3),
                for (final field in ['referer', 'origin', 'user_agent'])
                  if (line[field] != null) SelectableText('$field: ${line[field]}', style: const TextStyle(fontSize: 12), maxLines: 2),
                const SizedBox(height: 8),
                Text(checks[line['id']] ?? 'Not checked • Video not yet verified', style: const TextStyle(fontSize: 12)),
                Wrap(spacing: 6, children: [
                  TextButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('Copy URL'),
                    onPressed: () => _copy(line['stream_url'].toString())),
                  TextButton.icon(icon: const Icon(Icons.content_paste, size: 18), label: const Text('Copy details'),
                    onPressed: () => _copy(highlightCopyDetails(line))),
                  TextButton.icon(icon: const Icon(Icons.play_circle_outline, size: 18), label: const Text('Preview'),
                    onPressed: () => _preview(entry, line)),
                  TextButton.icon(icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(checking.contains(line['id']) ? 'Checking…' : 'Check'),
                    onPressed: checking.contains(line['id']) ? null : () async {
                      final id = line['id'].toString();
                      update(() => checking.add(id));
                      try {
                        final response = await widget.service.request(provider.id, 'check', {'entry_id': entry['id'], 'line_id': id});
                        final check = response['check'] as Map;
                        if (sheet.mounted) update(() => checks[id] = '${check['status'] == 'reachable' ? 'Reachable' : 'Failed / invalid media'} • HTTP ${check['http']} • ${check['ms']} ms • Video not verified');
                      } catch (_) {
                        if (sheet.mounted) update(() => checks[id] = 'Check failed. Reopen this highlight if its link changed.');
                      } finally { if (sheet.mounted) update(() => checking.remove(id)); }
                    }),
                ]),
              ]),
            )),
            if (lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No direct HLS / MP4 link is available from this source response.')),
            if (entry['source_page_url'] != null) Wrap(spacing: 8, children: [
              OutlinedButton.icon(icon: const Icon(Icons.open_in_new), label: const Text('Open original'),
                onPressed: () => _open(entry['source_page_url'].toString())),
              TextButton.icon(icon: const Icon(Icons.copy), label: const Text('Copy page'),
                onPressed: () => _copy(entry['source_page_url'].toString())),
            ]),
          ]),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _snapshots[_provider.id];
    final error = _errors[_provider.id];
    final loading = _inFlight.containsKey(_provider.id);
    final rows = highlightMaps(data?['entries']).where((row) => highlightMatchesQuery(row, _search.text) &&
      (!_nativeOnly || highlightMaps(row['lines']).isNotEmpty)).toList();
    final warnings = (data?['warnings'] as List? ?? []).map((value) => value.toString()).toSet();
    if (error != null) warnings.add(error);
    final updated = DateTime.tryParse(data?['updated_at']?.toString() ?? '')?.toLocal();
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights'), actions: [
        IconButton(tooltip: 'Open source website', onPressed: () => _open(_provider.url), icon: const Icon(Icons.open_in_new)),
        IconButton(tooltip: 'Refresh highlights', onPressed: loading || _provider.websiteOnly ? null : () {
          _load(_provider, force: true); setState(() {});
        }, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [for (final provider in HighlightsProvider.all)
            Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(provider.name),
              selected: _provider.id == provider.id, onSelected: (_) => _select(provider))),
          ])),
        Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: 'Search teams or highlights', prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close),
              onPressed: () => setState(() => _search.clear()))))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(children: [
          Expanded(child: Text('${rows.length} highlights${updated == null ? '' : ' • ${DateFormat('dd MMM, h:mm a').format(updated)}'}', style: const TextStyle(fontSize: 12))),
          FilterChip(label: const Text('Has video link'), selected: _nativeOnly,
            onSelected: (value) => setState(() => _nativeOnly = value)),
        ])),
        if (loading) const LinearProgressIndicator(),
        if (warnings.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Text(warnings.join(' '), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: loading ? null : () { _load(_provider, force: true); setState(() {}); }, child: const Text('Retry')),
        ])),
        Expanded(child: RefreshIndicator(onRefresh: () => _load(_provider, force: true), child: ListView.builder(
          key: PageStorageKey('highlights-${_provider.id}'), padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
          itemCount: rows.isEmpty ? 1 : rows.length,
          itemBuilder: (context, index) {
            if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              Text(_provider.websiteOnly ? 'Browse this source on its website. Direct media links are not connected.' :
                loading ? 'Loading highlights…' : 'No highlights to show. Try another source or clear your filters.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(icon: const Icon(Icons.open_in_new), label: Text('Open ${_provider.name}'), onPressed: () => _open(_provider.url)),
            ]));
            final row = rows[index]; final count = highlightMaps(row['lines']).length;
            return Card(child: ListTile(contentPadding: const EdgeInsets.all(12),
              leading: row['thumbnail_url'] == null ? const Icon(Icons.video_library_outlined) :
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(row['thumbnail_url'].toString(),
                  width: 64, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 48, child: Icon(Icons.video_library_outlined)))),
              title: Text(row['title']?.toString() ?? 'Highlights', maxLines: 3),
              subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Text(count > 0 ? '$count video links • Not yet verified' : 'Website player • Get links')),
              trailing: const Icon(Icons.chevron_right), onTap: () => _details(row)));
          },
        ))),
      ]),
    );
  }
}
