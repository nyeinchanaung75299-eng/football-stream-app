import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../channel_library.dart';

import '../native_player.dart';
import '../network_endpoints.dart';
import '../playback_routes.dart';
import '../public_guide_cache.dart';
import '../channel_match_search.dart';
import '../widgets/premium_bottom_nav.dart';
import 'home_page.dart';
import 'source_browser_page.dart';
import '../viewer_navigation.dart';
import '../viewer_tab_cache.dart';

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});
  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  static final PublicGuideCache<Map<String, dynamic>> _guideCache =
      PublicGuideCache<Map<String, dynamic>>();
  int _guideEpoch = 0;
  final search = TextEditingController();
  late Future<List<Map<String, dynamic>>> catalog;
  List<Map<String, dynamic>>? _lastChannels;
  late final ScrollController _channelScroll;
  bool opening = false;
  String selectedGroup = 'All';
  Map<String, int> groupPositions = const {};
  Map<String, String> nextFootball = const {};
  Map<String, List<Map<String, dynamic>>> footballProgrammes = const {};
  List<Map<String, dynamic>> matchChoices = const [];
  String? selectedMatchId;
  Set<String> epgLinkedIds = const {};
  bool guideLoaded = false;
  final library = ChannelLibrary.instance;
  String libraryFilter = 'all';

  @override
  void initState() {
    super.initState();
    final ui = ViewerTabCache.channelUi;
    selectedGroup = ui.group;
    selectedMatchId = ui.matchId;
    libraryFilter = ui.libraryFilter;
    search.text = ui.search;
    _channelScroll = ScrollController(initialScrollOffset: ui.scrollOffset);
    _lastChannels = ViewerTabCache.channelRows;
    groupPositions = ViewerTabCache.channelGroups;
    matchChoices = ViewerTabCache.channelMatches;
    // Show the last successful channel list immediately. A stale list stays
    // visible while a refresh races the same Cloudflare/Vercel routes.
    catalog = _lastChannels == null ? load() : Future.value(_lastChannels!);
    final refreshStale = _lastChannels != null && !ViewerTabCache.channelsFresh();
    if (refreshStale) {
      unawaited(refresh(silent: true));
    }
    // Channel logos are lazy Image widgets; fetch guide/fixture metadata
    // only after the first channel frame can paint, never on Viewer startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (refreshStale) return; // refresh() already started all three.
      if (!ViewerTabCache.channelGroupsFresh) unawaited(_loadGroupPositions());
      unawaited(_loadChannelEpg());
      if (!ViewerTabCache.channelMatchesFresh) unawaited(_loadMatchChoices());
    });
    library.load().then((_) { if (mounted) setState(() {}); });
  }

  /// Optional football-only EPG summary. Its failure never blocks channels.
  Future<void> _loadChannelEpg({bool refresh = false}) async {
    final generation = ++_guideEpoch;
    try {
      final now = DateTime.now().toUtc();
      final today = now.add(const Duration(hours: 6, minutes: 30));
      final date = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final data = await _guideCache.load(
        date,
        () => request('/tv-schedule?date=$date&days=3'),
        refresh: refresh,
      );
      final result = <String, String>{};
      final football = <String, List<Map<String, dynamic>>>{};
      final linked = <String>{};
      for (final raw in (data['channels'] as List? ?? const [])) {
        if (raw is! Map || raw['matchedEPG'] != true) continue;
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        linked.add(id);
        for (final item in (raw['programmes'] as List? ?? const [])) {
          if (item is! Map) continue;
          final title = (item['title'] ?? item['subtitle'] ?? '').toString();
          final extra = (item['description'] ?? '').toString();
          if (!currentFootballProgramme(item, now: now)) continue;
          final ms = (item['start'] as num?)?.toInt();
          if (ms == null) continue;
          final start = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
          if (start.isBefore(now.subtract(const Duration(hours: 3)))) continue;
          final label = title.isNotEmpty ? title : extra;
          final live = !start.isAfter(now);
          result.putIfAbsent(id, () => '${live ? 'LIVE' : 'NEXT'} • $label');
          football.putIfAbsent(id, () => []).add(Map<String, dynamic>.from(item));
        }
      }
      if (mounted && generation == _guideEpoch) setState(() {
        nextFootball = result;
        footballProgrammes = football;
        epgLinkedIds = linked;
        guideLoaded = true;
      });
    } catch (_) {
      // Keep channel grid interactive when guide or relay is offline.
    }
  }

  Future<void> _loadMatchChoices({bool force = false}) async {
    if (!force && ViewerTabCache.channelMatchesFresh) {
      if (mounted) setState(() => matchChoices = ViewerTabCache.channelMatches);
      return;
    }
    try {
      final data = await request('/matches');
      final earliest = DateTime.now().toUtc().subtract(const Duration(hours: 4));
      final matches = (data['matches'] as List? ?? const []).whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m)).where((m) {
        final time = DateTime.tryParse('${m['kickoff_at'] ?? ''}');
        return m['id'] != null && m['is_finished'] != true && time != null && !time.isBefore(earliest);
      }).toList()..sort((a, b) => '${a['kickoff_at']}'.compareTo('${b['kickoff_at']}'));
      ViewerTabCache.rememberChannelMatches(matches);
      if (mounted) setState(() {
        matchChoices = matches;
        if (!matches.any((m) => m['id'].toString() == selectedMatchId)) selectedMatchId = null;
      });
    } catch (_) { /* Channel and team search remain usable without fixtures. */ }
  }

  Future<void> _loadGroupPositions({bool force = false}) async {
    if (!force && ViewerTabCache.channelGroupsFresh) {
      if (mounted) setState(() => groupPositions = ViewerTabCache.channelGroups);
      return;
    }
    try {
      // Read public category metadata through the resolved Supabase relay.
      // If that relay is unavailable, the channel catalog still works.
      final rows = await Supabase.instance.client
          .from('channel_group_order')
          .select('category,position')
          .order('position')
          .timeout(const Duration(seconds: 7));
      final positions = {
        for (final row in rows)
          row['category'].toString(): (row['position'] as num).toInt(),
      };
      ViewerTabCache.rememberChannelGroups(positions);
      if (mounted) setState(() => groupPositions = positions);
    } catch (_) {
      // Keep default category order when its metadata can't be loaded.
    }
  }

  @override
  void dispose() {
    ViewerTabCache.channelUi = ViewerChannelsUiState(
      search: search.text,
      group: selectedGroup,
      matchId: selectedMatchId,
      libraryFilter: libraryFilter,
      scrollOffset: _channelScroll.hasClients
          ? _channelScroll.offset
          : ViewerTabCache.channelUi.scrollOffset,
    );
    _channelScroll.dispose();
    search.dispose();
    super.dispose();
  }

  bool matchesSearch(Map<String, dynamic> row) {
    final programmes = footballProgrammes[row['id'].toString()] ?? const <Map<String, dynamic>>[];
    if (!channelMatchesProgrammeQuery(row, programmes, search.text)) return false;
    if (selectedMatchId == null) return true;
    final match = matchChoices.where((m) => m['id'].toString() == selectedMatchId).firstOrNull;
    return match != null && programmes.any((p) => programmeCoversMatch(p, match));
  }

  Future<Map<String, dynamic>> request(String path) async {
    final bases = publicApiBases();
    final result = Completer<Map<String, dynamic>>();
    Object? lastError;
    var next = 0;
    var pending = 0;

    void startNext() {
      if (result.isCompleted || next >= bases.length) return;
      final base = bases[next++];
      pending++;
      () async {
        try {
          final response = await http
              .get(
                Uri.parse('$base$path'),
                headers: const {'Accept': 'application/json'},
              )
              .timeout(const Duration(seconds: 7));
          if (response.statusCode != 200) {
            throw StateError('HTTP ${response.statusCode}');
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['ok'] != true) {
            throw const FormatException('Invalid channel response');
          }
          if (!result.isCompleted) {
            rememberVerifiedPublicApiBase(base);
            result.complete(Map<String, dynamic>.from(decoded));
          }
        } catch (error) {
          lastError = error;
        } finally {
          pending--;
          if (!result.isCompleted) {
            // A failed route should not delay the next candidate.
            if (next < bases.length) startNext();
            if (next == bases.length && pending == 0) {
              result.completeError(
                StateError('Channel service unavailable: $lastError'),
              );
            }
          }
        }
      }();
    }

    startNext();
    final hedge = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (result.isCompleted || next >= bases.length) {
        timer.cancel();
      } else {
        startNext();
      }
    });
    try {
      return await result.future;
    } finally {
      hedge.cancel();
    }
  }

  Future<List<Map<String, dynamic>>> load({bool force = false}) async {
    final rows = await ViewerTabCache.loadChannels(() async {
      final data = await request('/channels');
      if (data['channels'] is! List) {
        throw const FormatException('Invalid channel catalog');
      }
      return (data['channels'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }, force: force);
    if (mounted && !identical(_lastChannels, rows)) {
      setState(() => _lastChannels = rows); // Includes successful empty [].
    }
    return rows;
  }

  Future<void> refresh({bool silent = false}) async {
    if (!mounted) return;
    final fresh = load(force: true);
    setState(() => catalog = fresh);
    unawaited(_loadGroupPositions(force: true));
    unawaited(_loadChannelEpg(refresh: true));
    unawaited(_loadMatchChoices(force: true));
    try {
      await fresh;
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Network unavailable. Showing saved channel list.'),
        ));
      }
    }
  }

  Future<void> watch(Map<String, dynamic> channel) async {
    if (opening) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final id = channel['id']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    setState(() => opening = true);
    try {
      final data = await request('/channels/$id/streams');
      if (data['streams'] is! List)
        throw const FormatException('Invalid channel lines');
      final lines = (data['streams'] as List)
          .whereType<Map>()
          .map((raw) {
            final row = Map<String, dynamic>.from(raw);
            final url = row['stream_url']?.toString() ?? '';
            final uri = Uri.tryParse(url);
            if (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                row['protected_proxy'] != true)
              return null;
            return <String, dynamic>{
              'id': row['id']?.toString(),
              'label': row['label']?.toString() ?? 'Server',
              'url': url,
              'streamType': row['stream_type']?.toString() ?? 'auto',
              'keyId': row['key_id']?.toString() ?? '',
              'keyData': row['key_data']?.toString() ?? '',
              'portraitStart': true,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active stream line for this channel.'),
          ),
        );
        return;
      }
      // Keep one selectable entry per Admin line while retaining a hidden
      // Vercel copy immediately after protected Cloudflare routes. The player
      // tries that copy only after the primary route fails, which lets Channels
      // open on networks where Cloudflare is unreachable without showing every
      // configured line twice in the server picker.
      final playerLines = addVpnFreePlaybackFallbacks(lines);
      NativePlayer.prewarm(sources: playerLines);
      unawaited(library.recordRecent(id).catchError((Object _) {}));
      await NativePlayer.open(
        context: context,
        sources: playerLines,
        selectedIndex: 0,
        title: channel['name']?.toString() ?? 'Channel',
        matchId: id,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open channel: $error')),
        );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  void navigate(int index) {
    ViewerTabCache.channelUi = ViewerChannelsUiState(
      search: search.text,
      group: selectedGroup,
      matchId: selectedMatchId,
      libraryFilter: libraryFilter,
      scrollOffset: _channelScroll.hasClients
          ? _channelScroll.offset
          : ViewerTabCache.channelUi.scrollOffset,
    );
    if (index == 6) {
      unawaited(refresh());
      return;
    }
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
      return;
    }
    final source = viewerSourceAt(index);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SourceBrowserPage(source: source),
      ),
    );
  }

  Future<void> _channelAction(String action, Map<String, dynamic> channel) async {
    final id = channel['id'].toString();
    try {
      if (action == 'favorite') {
        await library.toggleFavorite(id);
        if (mounted) setState(() {});
      } else {
        final opened = await launchUrl(Uri.https('t.me', '/NCAFootballViewer_bot',
            {'start': 'report_$id'}), mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('Telegram unavailable');
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not complete this action. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // Bottom navigation already identifies Channels; no duplicate title.
    appBar: AppBar(
      toolbarHeight: 0,
      automaticallyImplyLeading: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(53),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 5),
          child: SizedBox(height: 43, child: TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search channels, teams or matches',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? IconButton(
                      tooltip: 'Refresh channels',
                      onPressed: refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    )
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          )),
        ),
      ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: catalog,
      builder: (context, snapshot) {
        final rows = snapshot.hasData ? snapshot.data : _lastChannels;
        if (rows == null && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows == null) {
          return Center(
            child: Text('Channel catalog unavailable: ${snapshot.error}'),
          );
        }
        String groupOf(Map<String, dynamic> row) {
          final value = row['category']?.toString().trim() ?? '';
          return value.isEmpty ? 'Other' : value;
        }
        final groupCounts = <String, int>{};
        for (final row in rows) {
          final group = groupOf(row);
          groupCounts[group] = (groupCounts[group] ?? 0) + 1;
        }
        const groupPriority = <String>[
          'beIN Sports', 'TNT Sports', 'Fubo', 'FanCode', 'CazéTV',
          'Arena Sports', 'FOX Sports', 'D Sports', 'TSN', 'SporTV',
          'SPOTV', 'Premiere', 'Premier Sports',
        ];
        final availableGroups = groupCounts.keys.toList()
          ..sort((a, b) {
            final ai = groupPriority.indexOf(a);
            final bi = groupPriority.indexOf(b);
            final ar = groupPositions[a] ?? (ai < 0 ? 999 : ai);
            final br = groupPositions[b] ?? (bi < 0 ? 999 : bi);
            return ar.compareTo(br) != 0
                ? ar.compareTo(br)
                : a.compareTo(b);
          });
        final activeGroup =
            groupCounts.containsKey(selectedGroup) ? selectedGroup : 'All';
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final row in snapshot.data!.where(matchesSearch)) {
          final id = row['id'].toString();
          if (libraryFilter == 'favorites' && !library.favorites.contains(id)) continue;
          if (libraryFilter == 'recent' && !library.recent.contains(id)) continue;
          final category = groupOf(row);
          if (activeGroup != 'All' && category != activeGroup) continue;
          groups.putIfAbsent(libraryFilter == 'recent' ? 'Recently watched' : category, () => []).add(row);
        }
        if (libraryFilter == 'recent') {
          for (final rows in groups.values) {
            rows.sort((a,b) => library.recent.indexOf(a['id'].toString()).compareTo(library.recent.indexOf(b['id'].toString())));
          }
        }
        final orderedEntries = groups.entries.toList()
          ..sort((a, b) =>
              availableGroups.indexOf(a.key).compareTo(
                availableGroups.indexOf(b.key)));
        return RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            controller: _channelScroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                  child: Column(
                    children: [
                      // Compact channel and match filters share one row,
                      // rather than pushing the channel grid farther down.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('viewer-group-$activeGroup'),
                              value: activeGroup,
                              isExpanded: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Channel group',
                                labelStyle: TextStyle(fontSize: 11),
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'All',
                                  child: Text('All Channels',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12)),
                                ),
                                for (final group in availableGroups)
                                  DropdownMenuItem(
                                    value: group,
                                    child: Text(
                                      '$group (${groupCounts[group]})',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedGroup = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('viewer-match-${selectedMatchId ?? 'all'}'),
                              value: matchChoices.any((match) =>
                                  match['id'].toString() == selectedMatchId)
                                  ? selectedMatchId
                                  : 'all',
                              isExpanded: true,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Match',
                                labelStyle: TextStyle(fontSize: 11),
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All matches',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12)),
                                ),
                                for (final match in matchChoices)
                                  DropdownMenuItem(
                                    value: match['id'].toString(),
                                    child: Text(
                                      '${match['home_team']} vs ${match['away_team']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                              onChanged: matchChoices.isEmpty ? null : (value) =>
                                  setState(() {
                                selectedMatchId = value == 'all' ? null : value;
                                selectedGroup = 'All';
                                libraryFilter = 'all';
                                search.clear();
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (guideLoaded && (search.text.trim().isNotEmpty || selectedMatchId!=null))
                        const Padding(padding:EdgeInsets.only(bottom:6),child:Text(
                          'Team and match search uses verified football EPG. Channels without a guide can still be found by channel name.',
                          style:TextStyle(fontSize:11))),
                      SizedBox(
                        height: 45,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final group in const [
                              'All', 'beIN Sports', 'TNT Sports', 'Fubo',
                              'FanCode', 'CazéTV', 'Arena Sports', 'FOX Sports',
                            ])
                              if (group == 'All' ||
                                  groupCounts.containsKey(group))
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(group == 'All'
                                        ? 'All (${snapshot.data!.length})'
                                        : '$group (${groupCounts[group]})'),
                                    selected: activeGroup == group,
                                    onSelected: (_) =>
                                        setState(() => selectedGroup = group),
                                  ),
                                ),
                          ],
                        ),
                      ),
                      Wrap(spacing: 8, children: [
                        for (final entry in const {'favorites': 'Favorites', 'recent': 'Recently watched'}.entries)
                          FilterChip(label: Text(entry.value),
                            selected: libraryFilter == entry.key,
                            onSelected: (selected) => setState(() {
                              libraryFilter = selected ? entry.key : 'all'; selectedGroup = 'All';
                            })),
                      ]),
                    ],
                  ),
                ),
              ),
              if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      snapshot.data!.isEmpty
                          ? 'No published channels yet.'
                          : 'No matching channels.',
                    ),
                  ),
                ),
              for (final group in orderedEntries) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${group.key} (${group.value.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 176,
                        ),
                    itemCount: group.value.length,
                    itemBuilder: (context, index) {
                      final channel = group.value[index];
                      final image = channel['image_url']?.toString() ?? '';
                      final title = channel['name']?.toString() ?? 'Channel';
                      return SizedBox(
                        width: 160,
                        child: InkWell(
                          onTap: () => watch(channel),
                          child: Column(
                            children: [
                              Expanded(
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(fit: StackFit.expand, children: [
                                    Center(child: image.startsWith('https://')
                                        ? Image.network(
                                            image,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.tv),
                                          )
                                        : const Icon(Icons.tv, size: 38)),
                                    Positioned(top: 0, right: 0, child: PopupMenuButton<String>(
                                      tooltip: 'Channel options',
                                      icon: Icon(library.favorites.contains(channel['id'].toString())
                                          ? Icons.star_rounded : Icons.more_vert_rounded),
                                      onSelected: (action) => _channelAction(action, channel),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(value: 'favorite', child: Text(
                                          library.favorites.contains(channel['id'].toString())
                                              ? 'Remove favorite' : 'Add favorite')),
                                        const PopupMenuItem(value: 'report', child: Text('Report broken line')),
                                      ],
                                    )),
                                  ]),
                                ),
                              ),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (guideLoaded && epgLinkedIds.contains(channel['id']?.toString()))
                                const Text('● EPG',
                                  style: TextStyle(color: Color(0xFF54E6C1),
                                      fontSize: 9, fontWeight: FontWeight.w700)),
                              if (nextFootball.containsKey(channel['id']?.toString()))
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    nextFootball[channel['id']!.toString()]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF54E6C1),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
    bottomNavigationBar: PremiumBottomNav(
      selectedIndex: 6,
      onSelected: navigate,
    ),
  );
}
