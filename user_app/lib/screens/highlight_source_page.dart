import 'package:flutter/material.dart';
import '../highlight_source_service.dart';
import '../native_player.dart';
import '../viewer_navigation.dart';
import '../widgets/premium_bottom_nav.dart';
import '../widgets/premium_match_card.dart';
import '../widgets/source_match_filters.dart';
import 'channels_page.dart';
import 'source_browser_page.dart';

class HighlightsSourcePage extends StatefulWidget {
  const HighlightsSourcePage({
    super.key,
    this.service = const PublicHighlightsService(),
    this.onTabSelected,
  });
  final PublicHighlightsService service;
  final ValueChanged<int>? onTabSelected;
  @override
  State<HighlightsSourcePage> createState() => _HighlightsSourcePageState();
}

class _HighlightsSourcePageState extends State<HighlightsSourcePage> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  final _items = <Map<String, dynamic>>[];
  String _query = '';
  String? _league;
  bool _todayOnly = false;
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
    _searchController.dispose();
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
    if(index!=7 && widget.onTabSelected!=null){widget.onTabSelected!(index);return;}
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

  // Filters are local to already-loaded pages, with pagination preserved.
  List<Map<String, dynamic>> _visibleHighlights() {
    final query = _query.trim().toLowerCase();
    final nowMmt = DateTime.now().toUtc().add(const Duration(hours: 6, minutes: 30));
    return _items.where((row) {
      final league = (row['league'] ?? 'Highlights').toString();
      if (_league != null && _league != league) return false;
      final lookup = [league, row['home_team'], row['away_team'], row['title']]
          .where((value) => value != null).join(' ').toLowerCase();
      if (query.isNotEmpty && !lookup.contains(query)) return false;
      if (!_todayOnly) return true;
      final kickoff = DateTime.tryParse(row['kickoff_at']?.toString() ?? '');
      if (kickoff == null) return false;
      final mmt = kickoff.toUtc().add(const Duration(hours: 6, minutes: 30));
      return mmt.year == nowMmt.year && mmt.month == nowMmt.month &&
          mmt.day == nowMmt.day;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleHighlights();
    final leagues = _items.map((row) => (row['league'] ?? 'Highlights').toString()).toSet().toList()..sort();
    return Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          SourceMatchFilters(
            controller: _searchController,
            todayOnly: _todayOnly,
            leagues: leagues,
            league: _league,
            visibleCount: visible.length,
            onRefresh: () => _load(),
            onQueryChanged: (value) => setState(() => _query = value),
            onTodayChanged: (value) => setState(() => _todayOnly = value),
            onLeagueChanged: (value) => setState(() => _league = value),
          ),
          if (_loading || _opening) const LinearProgressIndicator(),
          if (_error != null)
            TextButton(
              onPressed: () => _load(),
              child: Text(_error!),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: visible.isEmpty
                    ? 1
                    : visible.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_items.isEmpty && _error != null)
                    return const SizedBox.shrink();
                  if (visible.isEmpty)
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _loading
                            ? 'Loading highlights…'
                            : _items.isEmpty ? 'No highlights found.' : 'No highlights for these filters.',
                      ),
                    );
                  if (index >= visible.length)
                    return TextButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: Text(
                        _loading ? 'Loading more…' : 'Load more highlights',
                      ),
                    );
                  final row = visible[index];
                  final lines = (row['lines'] as List? ?? []);
                  final score =
                      row['home_score'] == null || row['away_score'] == null
                      ? null
                      : "${row['home_score']}–${row['away_score']}";
                  final date = DateTime.tryParse(
                    row['kickoff_at']?.toString() ?? '',
                  )?.toUtc().add(const Duration(hours: 6, minutes: 30));
                  final hasLines = lines.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PremiumMatchCard(
                      league: (row['league'] ?? 'Highlights').toString(),
                      homeName: (row['home_team'] ?? row['title'] ?? 'Highlights').toString(),
                      awayName: (row['away_team'] ?? 'Video').toString(),
                      homeLogo: (row['home_logo_url'] ?? row['thumbnail_url'])?.toString(),
                      awayLogo: row['away_logo_url']?.toString(),
                      kickoff: date,
                      isLive: false,
                      canWatch: hasLines && !_opening,
                      actionLabel: hasLines ? 'WATCH HIGHLIGHTS' : 'HIGHLIGHTS NOT READY',
                      metaLabel: [
                        if (score != null) score,
                        if (row['is_finished'] == true) 'FT',
                      ].join(' • '),
                      timeLabel: date == null ? 'HIGHLIGHTS' : null,
                      onWatch: () => _play(row),
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
}
