import 'dart:async';
import 'package:flutter/material.dart';
import '../highlight_source_service.dart';
import '../native_player.dart';
import '../viewer_navigation.dart';
import '../widgets/premium_bottom_nav.dart';
import 'channels_page.dart';
import 'source_browser_page.dart';
import 'highlights_page.dart';

class HighlightsSourcePage extends StatefulWidget {
  const HighlightsSourcePage({
    super.key,
    this.service = const PublicHighlightsService(),
  });
  final PublicHighlightsService service;
  @override
  State<HighlightsSourcePage> createState() => _HighlightsSourcePageState();
}

class _HighlightsSourcePageState extends State<HighlightsSourcePage> {
  final _search = TextEditingController(), _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  Timer? _debounce;
  bool _loading = false, _hasMore = true, _opening = false;
  int _offset = 0, _epoch = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 300 &&
        _hasMore &&
        !_loading &&
        _error == null)
      _load(more: true);
  }

  Future<void> _load({bool more = false, bool force = false}) async {
    if (more && _loading) return;
    if (!more) _epoch++;
    final epoch = _epoch,
        offset = more ? _offset : 0,
        query = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.request(
        'catalog',
        offset: offset,
        query: query,
        force: force,
      );
      if (!mounted || epoch != _epoch) return;
      if (data['unavailable'] == true)
        throw StateError('Highlights unavailable');
      final rows = (data['entries'] as List? ?? []).whereType<Map>().map(
        (x) => Map<String, dynamic>.from(x),
      );
      setState(() {
        final map = <String, Map<String, dynamic>>{
          if (more)
            for (final row in _items) row['id'].toString(): row,
          for (final row in rows) row['id'].toString(): row,
        };
        _items
          ..clear()
          ..addAll(map.values);
        _offset = (data['next_offset'] as num?)?.toInt() ?? offset;
        _hasMore = data['has_more'] == true && _offset > offset;
      });
    } catch (_) {
      if (mounted && epoch == _epoch)
        setState(() => _error = 'Could not load highlights. Retry.');
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nearEnd();
        });
      }
    }
  }

  Future<void> _play(Map<String, dynamic> row) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final data = await widget.service.request(
        'details',
        entryId: row['id'].toString(),
      );
      final entry = data['entry'] as Map?;
      final lines = (entry?['lines'] as List? ?? []).whereType<Map>().toList();
      if (lines.isEmpty) throw StateError('No reachable video link');
      if (!mounted) return;
      int? selected = 0;
      if (lines.length > 1)
        selected = await showModalBottomSheet<int>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < lines.length; i++)
                ListTile(
                  title: Text(
                    lines[i]['label']?.toString() ?? 'Video ${i + 1}',
                  ),
                  subtitle: Text(
                    lines[i]['stream_type'].toString().toUpperCase(),
                  ),
                  onTap: () => Navigator.pop(sheet, i),
                ),
            ],
          ),
        );
      if (!mounted || selected == null) return;
      await NativePlayer.open(
        context: context,
        title: row['title']?.toString(),
        selectedIndex: selected,
        sources: [
          for (final line in lines)
            {
              'id': line['id'],
              'label': line['label'],
              'url': line['stream_url'],
              'streamType': line['stream_type'],
              'referer': line['referer'] ?? '',
              'origin': line['origin'] ?? '',
              'userAgent': line['user_agent'] ?? '',
            },
        ],
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This highlight could not be opened. Refresh and retry.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _navigate(int index) {
    if (index == 7) {
      _load(force: true);
      return;
    }
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => index == 6
            ? const ChannelsPage()
            : SourceBrowserPage(source: viewerSourceAt(index)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Highlights'),
      actions: [
        IconButton(
          tooltip: 'Published highlights',
          icon: const Icon(Icons.video_library_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const HighlightsPage()),
          ),
        ),
        IconButton(
          tooltip: 'Refresh highlights',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search teams, leagues or highlights',
            ),
            onChanged: (_) {
              _epoch++;
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => _load(force: true),
              );
            },
          ),
        ),
        if (_loading || _opening) const LinearProgressIndicator(),
        if (_error != null)
          TextButton(
            onPressed: () => _load(more: _items.isNotEmpty),
            child: Text(_error!),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _items.isEmpty
                  ? 1
                  : _items.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (_items.isEmpty)
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _loading ? 'Loading highlights…' : 'No highlights found.',
                    ),
                  );
                if (index >= _items.length)
                  return TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text(
                      _loading ? 'Loading more…' : 'Load more highlights',
                    ),
                  );
                final row = _items[index];
                return Card(
                  child: ListTile(
                    leading: row['thumbnail_url'] == null
                        ? const Icon(Icons.movie_outlined)
                        : Image.network(
                            row['thumbnail_url'].toString(),
                            width: 64,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.movie_outlined),
                          ),
                    title: Text(row['title']?.toString() ?? 'Highlights'),
                    subtitle: Text(
                      [row['league'], row['published_at'], row['duration']]
                          .where((x) => x != null && x.toString().isNotEmpty)
                          .join(' • '),
                    ),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: _opening ? null : () => _play(row),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: PremiumBottomNav(
      selectedIndex: 7,
      onSelected: _navigate,
    ),
  );
}
