import 'highlight_matches_page.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/highlights_service.dart';

/// Session-scoped, lazy direct-link catalogue. No media is downloaded until
/// the Admin requests extracted links or an explicit first-byte link recheck.
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
  final _scroll = ScrollController();
  Timer? _debounce;
  int _epoch = 0, _nextOffset = 0;
  bool _hasMore = true;
  String _loadedQuery = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _loadNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 300 &&
        _hasMore &&
        _inFlight == null &&
        _error == null) _load(more: true);
  }

  Future<void> _load({bool force = false, bool more = false}) {
    if (_inFlight != null && more) return _inFlight!;
    if (!force &&
        !more &&
        _loadedQuery == _search.text.trim() &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    if (!more) _epoch++;
    final operation = _fetch(
        force, more, more ? _nextOffset : 0, _search.text.trim(), _epoch);
    _inFlight = operation;
    operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadNearEnd();
        });
      }
    });
    return operation;
  }

  Future<void> _fetch(
      bool force, bool more, int offset, String query, int epoch) async {
    try {
      final data = await widget.service.request(
          'catalog', {'force': force, 'offset': offset, 'query': query});
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = null;
        if (data['unavailable'] != true || _data == null) {
          final entries = <String, Map<String, dynamic>>{
            if (more)
              for (final row in highlightMaps(_data?['entries']))
                row['id'].toString(): row,
            for (final row in highlightMaps(data['entries']))
              row['id'].toString(): row,
          };
          _data = {...data, 'entries': entries.values.toList()};
          _hasMore = data['has_more'] == true;
          _nextOffset = (data['next_offset'] as num?)?.toInt() ?? offset;
          _loadedQuery = query;
        }
        if (data['unavailable'] == true) {
          _error = (data['warnings'] as List? ??
                  ['Could not extract highlight links.'])
              .join(' ');
        } else if (data['stale'] != true) {
          _loadedAt = DateTime.now();
        }
      });
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() => _error =
            'Could not refresh. Showing the last successful links, if available.');
    }
  }

  void _notice(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      _notice('Copied.');
    } catch (_) {
      _notice('Copy failed. Select and copy the URL shown in the details.');
    }
  }

  Future<void> _details(Map<String, dynamic> row) async {
    if (_opening) return;
    setState(() => _opening = true);
    Map<String, dynamic> entry;
    try {
      final result =
          await widget.service.request('details', {'entry_id': row['id']});
      entry = Map<String, dynamic>.from(result['entry'] as Map);
    } catch (_) {
      _notice('Could not extract links. Please retry.');
      return;
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) return;
    final lines = highlightMaps(entry['lines']);
    setState(() {
      final entries = highlightMaps(_data?['entries']);
      _data = {
        ...?_data,
        'entries': [
          for (final item in entries) item['id'] == entry['id'] ? entry : item
        ]
      };
    });
    if (lines.isEmpty) {
      _notice(
          'No working direct link was returned by this source. Refresh later to try again.');
      return;
    }
    final checks = <String, String>{};
    final checking = <String>{};
    final adding = <String>{}, added = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
          builder: (_, update) => ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheet).height * .85),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Select Stream Quality',
                            style: Theme.of(sheet).textTheme.titleLarge),
                        Text(entry['title']?.toString() ?? 'Highlights',
                            style: Theme.of(sheet).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text('${lines.length} extracted links • DasFootball'),
                        const Text(
                            'ADD saves to Highlights. Video playback is not verified.',
                            style: TextStyle(fontSize: 12)),
                        for (final line in lines)
                          Card(
                            margin: const EdgeInsets.only(top: 12),
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(
                                                  '${line['label']} • ${line['stream_type'].toString().toUpperCase()}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              SelectableText(
                                                  line['stream_url'].toString(),
                                                  maxLines: 1),
                                              for (final field in [
                                                'referer',
                                                'origin',
                                                'user_agent'
                                              ])
                                                if (line[field] != null)
                                                  SelectableText(
                                                      '$field: ${line[field]}',
                                                      style: const TextStyle(
                                                          fontSize: 10.5),
                                                      maxLines: 1),
                                              const SizedBox(height: 8),
                                              Text(
                                                  checks[line['id']] ??
                                                      (line['link_check'] is Map
                                                          ? 'Link reachable • HTTP ${(line['link_check'] as Map)['http']}'
                                                          : 'Link not checked'),
                                                  style: const TextStyle(
                                                      fontSize: 10.5)),
                                            ])),
                                        IconButton(
                                            tooltip: 'Copy URL',
                                            icon:
                                                const Icon(Icons.copy_rounded),
                                            onPressed: () => _copy(
                                                line['stream_url'].toString())),
                                        FilledButton(
                                            onPressed: adding
                                                    .contains(line['id'])
                                                ? null
                                                : () async {
                                                    final id =
                                                        line['id'].toString();
                                                    update(
                                                        () => adding.add(id));
                                                    try {
                                                      final destinations = await widget.service.destinations();
                                                      if (!sheet.mounted) return;
                                                      final matchId = await chooseHighlightMatch(sheet, destinations);
                                                      if (matchId == null || !sheet.mounted) return;
                                                      if (matchId.isEmpty) {
                                                        await widget.service.save(entry, line);
                                                      } else {
                                                        await widget.service.save(entry, line, matchId: matchId);
                                                      }
                                                      if (sheet.mounted)
                                                        update(() =>
                                                            added.add(id));
                                                      _notice(
                                                          'Added to Highlights.');
                                                    } catch (_) {
                                                      _notice(
                                                          'Could not add highlight. Please retry.');
                                                    } finally {
                                                      if (sheet.mounted)
                                                        update(() =>
                                                            adding.remove(id));
                                                    }
                                                  },
                                            child:
                                                Text(adding.contains(line['id'])
                                                    ? 'ADDING…'
                                                    : added.contains(line['id'])
                                                        ? 'ADDED ✓'
                                                        : 'ADD')),
                                      ]),
                                      Wrap(spacing: 6, children: [
                                        TextButton.icon(
                                            icon: const Icon(
                                                Icons.content_paste,
                                                size: 18),
                                            label: const Text('Copy details'),
                                            onPressed: () => _copy(
                                                highlightCopyDetails(line))),
                                        TextButton.icon(
                                            icon: const Icon(
                                                Icons.fact_check_outlined,
                                                size: 18),
                                            label: Text(
                                                checking.contains(line['id'])
                                                    ? 'Checking…'
                                                    : 'Check link'),
                                            onPressed: checking
                                                    .contains(line['id'])
                                                ? null
                                                : () async {
                                                    final id =
                                                        line['id'].toString();
                                                    update(
                                                        () => checking.add(id));
                                                    try {
                                                      final response =
                                                          await widget.service
                                                              .request(
                                                                  'check', {
                                                        'entry_id': entry['id'],
                                                        'line_id': id
                                                      });
                                                      final check =
                                                          response['check']
                                                              as Map;
                                                      if (sheet.mounted)
                                                        update(() => checks[
                                                                id] =
                                                            '${check['status'] == 'reachable' ? 'Link reachable' : 'Failed / invalid link'} • HTTP ${check['http']} • ${check['ms']} ms');
                                                    } catch (_) {
                                                      if (sheet.mounted)
                                                        update(() => checks[
                                                                id] =
                                                            'Check failed. Refresh the list if this link changed.');
                                                    } finally {
                                                      if (sheet.mounted)
                                                        update(() => checking
                                                            .remove(id));
                                                    }
                                                  }),
                                      ]),
                                    ])),
                          ),
                        if (lines.isEmpty)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                  'No direct HLS / MP4 link was extracted. Refresh the list.')),
                      ]),
                ),
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = _inFlight != null;
    final rows = highlightMaps(_data?['entries'])
        .where((row) => highlightMatchesQuery(row, _search.text))
        .toList();
    final warnings = (_data?['warnings'] as List? ?? [])
        .map((value) => value.toString())
        .toSet();
    if (_error != null) warnings.add(_error!);
    final updated =
        DateTime.tryParse(_data?['updated_at']?.toString() ?? '')?.toLocal();
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights'), actions: [
        IconButton(
            tooltip: 'Saved highlights',
            icon: const Icon(Icons.video_library_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SavedHighlightsPage(service: widget.service)))),
        IconButton(
            tooltip: 'Refresh highlights',
            onPressed: loading
                ? null
                : () {
                    _load(force: true);
                    setState(() {});
                  },
            icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextField(
                controller: _search,
                onChanged: (_) {
                  setState(() {
                    _hasMore = false;
                    _epoch++;
                  });
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350),
                      () => _load(force: true));
                },
                decoration: InputDecoration(
                    hintText: 'Search teams or highlights',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => _search.clear());
                              _load(force: true);
                            })))),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'DasFootball • ${rows.length} highlights${updated == null ? '' : ' • ${DateFormat('dd MMM, h:mm a').format(updated)}'}',
                    style: const TextStyle(fontSize: 12)))),
        if (loading || _opening) const LinearProgressIndicator(),
        if (warnings.isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(warnings.join(' '),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton(
                    onPressed: loading
                        ? null
                        : () {
                            _load(force: true);
                            setState(() {});
                          },
                    child: const Text('Retry')),
              ])),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () => _load(force: true),
                child: ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  key: const PageStorageKey('highlights-dasfootball'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  itemCount:
                      rows.isEmpty ? 1 : rows.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (rows.isEmpty)
                      return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(loading
                              ? 'Extracting highlight links…'
                              : 'No extracted links to show. Refresh or clear your search.'));
                    if (index >= rows.length)
                      return TextButton(
                          onPressed: loading ? null : () => _load(more: true),
                          child: Text(loading
                              ? 'Loading more…'
                              : 'Load more highlights'));
                    final row = rows[index];
                    final count = highlightMaps(row['lines']).length;
                    final published =
                        DateTime.tryParse(row['published_at']?.toString() ?? '')
                            ?.toLocal();
                    return Card(
                        child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: row['thumbnail_url'] == null
                                ? const Icon(Icons.link)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                        row['thumbnail_url'].toString(),
                                        width: 64,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(
                                                width: 64,
                                                height: 48,
                                                child: Icon(Icons.link)))),
                            title: Text(
                                row['title']?.toString() ?? 'Highlights',
                                maxLines: 3),
                            subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                    'Get links • $count extracted${published == null ? '' : '\n${DateFormat('dd MMM, h:mm a').format(published)}'}')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _opening ? null : () => _details(row)));
                  },
                ))),
      ]),
    );
  }
}

class SavedHighlightsPage extends StatefulWidget {
  const SavedHighlightsPage({super.key, required this.service});
  final HighlightsService service;
  @override
  State<SavedHighlightsPage> createState() => _SavedHighlightsPageState();
}

class _SavedHighlightsPageState extends State<SavedHighlightsPage> {
  final items = <Map<String, dynamic>>[];
  String? deleting, error;
  bool loading = false, hasMore = true;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.service.saved(offset: more ? items.length : 0);
      if (!mounted) return;
      setState(() {
        if (!more) items.clear();
        final ids = items.map((r) => r['id']).toSet();
        items.addAll(next.where((r) => ids.add(r['id'])));
        hasMore = next.length == 50;
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load. Retry');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Delete highlight?'),
                content: Text(row['title']?.toString() ?? 'Highlight'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Delete'))
                ]));
    if (yes != true || !mounted) return;
    setState(() => deleting = row['id'].toString());
    try {
      await widget.service.remove(row['id'].toString());
      if (mounted) reload();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete failed. Refresh and retry.')));
    } finally {
      if (mounted) setState(() => deleting = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Saved highlights'), actions: [
        IconButton(
            onPressed: loading ? null : reload, icon: const Icon(Icons.refresh))
      ]),
      body: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  TextButton(
                      onPressed:
                          loading ? null : () => reload(more: items.isNotEmpty),
                      child: Text(error!)),
                if (!loading && items.isEmpty && error == null)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'No saved highlights. Use ADD on a source link.')),
                for (final row in items)
                  ListTile(
                      title: Text(row['title']?.toString() ?? 'Highlight'),
                      subtitle: Text(row['video_url']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                          tooltip: 'Delete highlight',
                          onPressed: deleting == null && !loading
                              ? () => remove(row)
                              : null,
                          icon: const Icon(Icons.delete_outline))),
                if (hasMore && items.isNotEmpty)
                  OutlinedButton(
                      onPressed: loading ? null : () => reload(more: true),
                      child: const Text('Load more highlights')),
              ])));
}
