import 'package:flutter/material.dart';
import '../highlight_source_service.dart';
import '../native_player.dart';
import '../viewer_navigation.dart';
import '../widgets/premium_bottom_nav.dart';
import 'channels_page.dart';
import 'source_browser_page.dart';

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
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
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

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    if (!more) _epoch++;
    final epoch = _epoch, offset = more ? _offset : 0;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.service.list(offset);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        final map = <String, Map<String, dynamic>>{
          if (more)
            for (final row in _items) row['id'].toString(): row,
          for (final row in rows) row['id'].toString(): row,
        };
        _items
          ..clear()
          ..addAll(map.values);
        _offset = offset + rows.length;
        _hasMore = rows.length == PublicHighlightsService.pageSize;
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
      final lines = (row['lines'] as List? ?? []).whereType<Map>().toList();
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
      _load();
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

  Widget _badge(dynamic url) => SizedBox(
    width: 52,
    height: 52,
    child: url == null || url.toString().isEmpty
        ? const Icon(Icons.shield_outlined)
        : Image.network(
            url.toString(),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined),
          ),
  );

  Widget _team(dynamic name, dynamic url) => Column(
    children: [
      _badge(url),
      Text(name.toString(), textAlign: TextAlign.center),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          if (_loading || _opening) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(
              onPressed: () => _load(more: _items.isNotEmpty),
              child: Text(_error!),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _items.isEmpty
                    ? 1
                    : _items.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_items.isEmpty && _error != null)
                    return const SizedBox.shrink();
                  if (_items.isEmpty)
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _loading
                            ? 'Loading highlights…'
                            : 'No highlights found.',
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
                  final lines = (row['lines'] as List? ?? []);
                  final score =
                      row['home_score'] == null || row['away_score'] == null
                      ? null
                      : "${row['home_score']}–${row['away_score']}";
                  final date = DateTime.tryParse(
                    row['kickoff_at']?.toString() ?? '',
                  )?.toUtc().add(const Duration(hours: 6, minutes: 30));
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          if (row['league'] != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(row['league'].toString()),
                            ),
                          if (row['home_team'] != null)
                            Row(
                              children: [
                                Expanded(
                                  child: _team(
                                    row['home_team'],
                                    row['home_logo_url'],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Column(
                                    children: [
                                      if (score != null)
                                        Text(
                                          score,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineSmall,
                                        ),
                                      if (row['is_finished'] == true)
                                        const Text('FT'),
                                      if (date != null)
                                        Text(
                                          MaterialLocalizations.of(
                                            context,
                                          ).formatShortMonthDay(date),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _team(
                                    row['away_team'],
                                    row['away_logo_url'],
                                  ),
                                ),
                              ],
                            )
                          else
                            ListTile(
                              leading: _badge(row['thumbnail_url']),
                              title: Text(
                                row['title']?.toString() ?? 'Highlights',
                              ),
                            ),
                          const Divider(),
                          if (lines.isEmpty)
                            const Text('Highlights not available yet')
                          else
                            FilledButton.icon(
                              onPressed: _opening ? null : () => _play(row),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Watch Highlights'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: PremiumBottomNav(
      selectedIndex: 7,
      onSelected: _navigate,
    ),
  );
}
