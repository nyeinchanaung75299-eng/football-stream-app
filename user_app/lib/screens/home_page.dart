import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../native_player.dart';
import 'soco_page.dart';
import 'network_diagnostics_page.dart';
import '../widgets/theme_mode_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;
  int _sourceTab = 0;
  String? _fallbackLabel;

  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue:
        'https://football-api.nyeinchanaung.us.ci',
  );

  static const _mirrorBase =
      'https://nyeinchanaung75299-eng.github.io/'
      'football-stream-app/matches.json';

  @override
  void initState() {
    super.initState();
    _future = loadMatches();
    _channel = Supabase.instance.client
        .channel('v7-pro-featured')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'matches',
          callback: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) refresh(silent: true);
            });
          },
        )
        .subscribe();
  }

  List<Map<String, dynamic>> _sortMatchesChronologically(
    List<Map<String, dynamic>> rows,
  ) {
    rows.sort((a, b) {
      final aText = a['kickoff_at']?.toString();
      final bText = b['kickoff_at']?.toString();

      final aTime = aText == null ? null : DateTime.tryParse(aText);
      final bTime = bText == null ? null : DateTime.tryParse(bText);

      if (aTime == null && bTime == null) {
        final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
        return aOrder.compareTo(bOrder);
      }
      if (aTime == null) return 1;
      if (bTime == null) return -1;

      final timeCompare = aTime.compareTo(bTime);
      if (timeCompare != 0) return timeCompare;

      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      return aOrder.compareTo(bOrder);
    });

    return rows;
  }

  List<Map<String, dynamic>> _decodeMatches(String body) {
    final decoded = jsonDecode(body);
    final raw = decoded is Map<String, dynamic>
        ? decoded['matches']
        : decoded;

    if (raw is! List) {
      throw const FormatException('Match feed is invalid.');
    }

    return _sortMatchesChronologically(
      raw
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPublicApi() async {
    final base = _publicApiBase.trim();
    if (base.isEmpty) {
      throw const FormatException('Public API is not configured.');
    }

    final uri = Uri.parse(
      '${base.replaceAll(RegExp(r"/+$"), "")}/matches',
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 7));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Public API returned HTTP ${response.statusCode}');
    }

    return _decodeMatches(response.body);
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiStreams(
    String matchId,
  ) async {
    final base = _publicApiBase.trim();
    if (base.isEmpty) {
      throw const FormatException('Public API is not configured.');
    }

    final cleanBase = base.replaceAll(RegExp(r"/+$"), "");
    final uri = Uri.parse(
      '$cleanBase/matches/${Uri.encodeComponent(matchId)}/streams',
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 7));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Public stream API returned HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);
    final raw = decoded is Map<String, dynamic>
        ? decoded['streams']
        : decoded;

    if (raw is! List) {
      throw const FormatException('Stream response is invalid.');
    }

    return raw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _resolveLinks(
    Map<String, dynamic> match,
  ) async {
    var links = playableLinks(match['stream_links']);
    if (links.isNotEmpty) return links;

    final matchId = match['id']?.toString().trim() ?? '';
    if (matchId.isEmpty) return const [];

    try {
      links = playableLinks(await _loadPublicApiStreams(matchId));
      if (links.isNotEmpty) return links;
    } catch (_) {}

    try {
      final data = await Supabase.instance.client
          .from('stream_links')
          .select(
            'id,label,resolution,stream_type,stream_url,referer,origin,'
            'key_id,key_data,use_webview,webview_url,is_active,priority,'
            'available_from,expires_at,health_status',
          )
          .eq('match_id', matchId)
          .eq('is_active', true)
          .order('priority')
          .timeout(const Duration(seconds: 6));

      links = playableLinks(data);
      if (links.isNotEmpty) return links;
    } catch (_) {}

    return const [];
  }

  Future<List<Map<String, dynamic>>> _loadMirror() async {
    final bucket =
        DateTime.now().millisecondsSinceEpoch ~/ (5 * 60 * 1000);
    final uri = Uri.parse('$_mirrorBase?v=$bucket');

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Mirror returned HTTP ${response.statusCode}');
    }

    return _decodeMatches(response.body);
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('''
          id,league,home_team,away_team,home_logo_url,away_logo_url,
          kickoff_at,is_live,sort_order,home_score,away_score,status_short,
          status_elapsed,is_finished,is_featured,publish_state,
          stream_links(
            id,label,resolution,stream_type,stream_url,referer,origin,
            key_id,key_data,use_webview,webview_url,is_active,priority,
            available_from,expires_at,health_status
          )
        ''')
        .eq('is_active', true)
        .eq('publish_state', 'published')
        .eq('is_featured', true)
        .order('kickoff_at')
        .order('sort_order')
        .timeout(const Duration(seconds: 5));

    return _sortMatchesChronologically(
      List<Map<String, dynamic>>.from(data),
    );
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final winner = Completer<List<Map<String, dynamic>>>();
    var failed = 0;

    void succeed(
      List<Map<String, dynamic>> rows,
      String? sourceLabel,
    ) {
      if (winner.isCompleted) return;
      _fallbackLabel = sourceLabel;
      if (mounted) setState(() {});
      winner.complete(rows);
    }

    Future<void> attempt(
      Future<List<Map<String, dynamic>>> future,
      String? sourceLabel,
    ) async {
      try {
        final rows = await future;
        succeed(rows, sourceLabel);
      } catch (_) {
        failed += 1;
        if (failed >= 2 && !winner.isCompleted) {
          try {
            final rows = await _loadMirror();
            succeed(rows, 'Backup feed');
          } catch (error) {
            if (!winner.isCompleted) winner.completeError(error);
          }
        }
      }
    }

    unawaited(
      attempt(
        _loadSupabaseMatches(),
        null,
      ),
    );
    unawaited(
      attempt(
        _loadPublicApi(),
        'Fast public API',
      ),
    );

    return winner.future;
  }

  Future<void> refresh({bool silent = false}) async {
    final next = loadMatches();
    if (mounted) setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      if (!silent) rethrow;
    }
  }

  List<Map<String, dynamic>> playableLinks(dynamic raw) {
    final now = DateTime.now();
    final rows = List<Map<String, dynamic>>.from(raw ?? const []);
    final filtered = rows.where((row) {
      if (row['is_active'] != true) return false;
      final fromText = row['available_from']?.toString();
      final expiryText = row['expires_at']?.toString();
      if (fromText != null && fromText.isNotEmpty) {
        if (now.isBefore(DateTime.parse(fromText).toLocal())) return false;
      }
      if (expiryText != null && expiryText.isNotEmpty) {
        if (!now.isBefore(DateTime.parse(expiryText).toLocal())) return false;
      }
      final useWeb = row['use_webview'] == true;
      final url = useWeb
          ? (row['webview_url']?.toString() ?? '')
          : (row['stream_url']?.toString() ?? '');
      return url.trim().isNotEmpty;
    }).toList();

    int healthRank(Map<String, dynamic> row) {
      switch ((row['health_status'] ?? 'unknown').toString()) {
        case 'healthy':
          return 0;
        case 'unknown':
          return 1;
        case 'slow':
          return 2;
        default:
          return 3;
      }
    }

    int formatRank(Map<String, dynamic> row) {
      if (row['use_webview'] == true) return 9;
      final type = (row['stream_type'] ?? 'auto').toString().toLowerCase();
      final url = (row['stream_url'] ?? '').toString().toLowerCase();

      if (type == 'hls' || type == 'm3u8' || url.contains('.m3u8')) return 0;
      if (type == 'dash' || type == 'mpd' || url.contains('.mpd')) return 1;
      if (type == 'mp4' || url.contains('.mp4')) return 2;
      if (type == 'auto') return 3;
      if (type == 'flv' || url.contains('.flv')) return 4;
      return 5;
    }

    filtered.sort((a, b) {
      final h = healthRank(a).compareTo(healthRank(b));
      if (h != 0) return h;

      // HLS first gives Android, iPhone and browser clients the most portable
      // source before falling back to DASH/direct/FLV.
      final f = formatRank(a).compareTo(formatRank(b));
      if (f != 0) return f;

      final ap = (a['priority'] as num?)?.toInt() ?? 100;
      final bp = (b['priority'] as num?)?.toInt() ?? 100;
      return ap.compareTo(bp);
    });
    return filtered;
  }

  Future<void> openPlayer(Map<String, dynamic> match) async {
    final links = await _resolveLinks(match);
    if (links.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream is not available yet.')),
      );
      return;
    }

    final nativeSources = links
        .where((x) => x['use_webview'] != true)
        .map((x) => <String, dynamic>{
              'id': x['id']?.toString(),
              'label': (x['label'] ?? x['resolution'] ?? 'Server').toString(),
              'streamType': (x['stream_type'] ?? 'auto').toString(),
              'url': (x['stream_url'] ?? '').toString(),
              'referer': (x['referer'] ?? '').toString(),
              'origin': (x['origin'] ?? '').toString(),
              'keyId': (x['key_id'] ?? '').toString(),
              'keyData': (x['key_data'] ?? '').toString(),
            })
        .where((x) => (x['url'] as String).trim().isNotEmpty)
        .toList();

    if (nativeSources.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This match currently has no native stream.')),
      );
      return;
    }

    var selectedIndex = 0;

    if (nativeSources.length > 1) {
      final picked = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final colors = Theme.of(sheetContext).colorScheme;

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: nativeSources.length <= 4 ? .52 : .72,
            minChildSize: .38,
            maxChildSize: .90,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Choose line',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${match['home_team']} vs ${match['away_team']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${nativeSources.length} lines',
                            style: TextStyle(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
                      itemCount: nativeSources.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final source = nativeSources[index];
                        final label =
                            (source['label'] ?? 'Server ${index + 1}')
                                .toString();
                        final type =
                            (source['streamType'] ?? 'auto')
                                .toString()
                                .toUpperCase();

                        return ListTile(
                          minTileHeight: 66,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colors.outlineVariant
                                  .withValues(alpha: .55),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                colors.primaryContainer.withValues(alpha: .7),
                            foregroundColor: colors.onPrimaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            type == 'HLS' || type == 'M3U8'
                                ? 'HLS • Preferred'
                                : (type == 'AUTO' ? 'Auto / Direct' : type),
                          ),
                          trailing: const Icon(Icons.play_arrow_rounded),
                          onTap: () =>
                              Navigator.pop(sheetContext, index),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      if (picked == null) return;
      selectedIndex = picked;
    }

    try {
      await NativePlayer.open(
        sources: nativeSources,
        selectedIndex: selectedIndex,
        title: '${match['home_team']} vs ${match['away_team']}',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player could not be opened.')),
      );
    }
  }

  Future<void> _openAppMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.sports_soccer_rounded,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Football Live Pro',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'V9.5 • Premium viewer',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text(
                  'Appearance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('System, light or dark mode'),
                trailing: const ThemeModeButton(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text(
                  'Connection diagnostics',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Check API and fallback connectivity'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NetworkDiagnosticsPage(),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.public_rounded),
                title: const Text(
                  'Soco',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Open the secondary live source'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SocoPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final c = _channel;
    if (c != null) Supabase.instance.client.removeChannel(c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.sports_soccer_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Football Live'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'PRO',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Menu',
            onPressed: _openAppMenu,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.live_tv_rounded),
                  label: Text('Main Live'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.public_rounded),
                  label: Text('Soco'),
                ),
              ],
              selected: {_sourceTab},
              showSelectedIcon: false,
              onSelectionChanged: (value) async {
                final next = value.first;
                if (next == 1) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SocoPage(),
                    ),
                  );
                  if (mounted) {
                    setState(() => _sourceTab = 0);
                  }
                  return;
                }
                setState(() => _sourceTab = 0);
              },
            ),
          ),
          if (_fallbackLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: .50),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _fallbackLabel == 'Fast public API'
                          ? Icons.bolt_rounded
                          : Icons.cloud_done_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fallbackLabel == 'Fast public API'
                            ? 'Connected through secure edge'
                            : 'Backup feed active',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done &&
                          !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError && !snapshot.hasData) {
                        return _StateMessage(
                          icon: Icons.wifi_off_rounded,
                          title: 'Couldn’t load matches',
                          subtitle: 'Check the connection and try again.',
                          onPressed: refresh,
                        );
                      }
                      final matches = snapshot.data ?? const [];
                      if (matches.isEmpty) {
                        return _StateMessage(
                          icon: Icons.sports_soccer_outlined,
                          title: 'No matches now',
                          subtitle: 'Selected big matches will appear here.',
                          onPressed: refresh,
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                          itemCount: matches.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final m = matches[index];
                            final links = playableLinks(m['stream_links']);
                            final nativeLinkCount = links.where((x) {
                              if (x['use_webview'] == true) return false;
                              return (x['stream_url']?.toString() ?? '')
                                  .trim()
                                  .isNotEmpty;
                            }).length;
                            final fallbackCount =
                                (m['stream_count'] as num?)?.toInt() ?? 0;
                            final displayCount = nativeLinkCount > 0
                                ? nativeLinkCount
                                : fallbackCount;
                            return _MatchCard(
                              match: m,
                              canWatch: displayCount > 0,
                              linkCount: displayCount,
                              onWatch: () => openPlayer(m),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.canWatch,
    required this.linkCount,
    required this.onWatch,
  });

  final Map<String, dynamic> match;
  final bool canWatch;
  final int linkCount;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kickoff = DateTime.parse(match['kickoff_at']).toLocal();
    final live = match['is_live'] == true;
    final finished = match['is_finished'] == true;
    final rawHomeScore = (match['home_score'] as num?)?.toInt();
    final rawAwayScore = (match['away_score'] as num?)?.toInt();
    final homeScore = rawHomeScore ?? 0;
    final awayScore = rawAwayScore ?? 0;
    final elapsed = (match['status_elapsed'] as num?)?.toInt();
    final hasStoredScore = rawHomeScore != null && rawAwayScore != null;
    final showScore = live || finished || hasStoredScore;

    return Card(
      margin: EdgeInsets.zero,
      elevation: live ? 2 : 0,
      shadowColor: colors.primary.withValues(alpha: .10),
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: live
              ? Colors.redAccent.withValues(alpha: .35)
              : colors.outlineVariant.withValues(alpha: .4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (match['league'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (live)
                  _Pill(
                    text: elapsed == null ? 'LIVE' : "LIVE  $elapsed'",
                    color: Colors.redAccent,
                  )
                else if (finished)
                  const _Pill(text: 'FT', color: Colors.blueGrey)
                else
                  _Pill(
                    text: DateFormat('HH:mm').format(kickoff),
                    color: colors.primary,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: _Team(
                    name: '${match['home_team']}',
                    logo: match['home_logo_url']?.toString(),
                  ),
                ),
                SizedBox(
                  width: 78,
                  child: Center(
                    child: showScore
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: live
                                  ? Colors.redAccent.withValues(alpha: .08)
                                  : colors.surfaceContainerHighest
                                      .withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$homeScore - $awayScore',
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'VS',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM').format(kickoff),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Expanded(
                  child: _Team(
                    name: '${match['away_team']}',
                    logo: match['away_logo_url']?.toString(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: canWatch ? onWatch : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  canWatch
                      ? (linkCount > 1 ? 'WATCH • $linkCount LINES' : 'WATCH')
                      : 'NOT READY',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({required this.name, required this.logo});

  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasLogo = logo != null && logo!.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(15),
          ),
          child: hasLogo
              ? Image.network(
                  logo!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.shield_outlined, size: 26),
                )
              : const Icon(Icons.shield_outlined, size: 26),
        ),
        const SizedBox(height: 5),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.title, required this.subtitle, required this.onPressed});
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onPressed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: colors.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => onPressed(), child: const Text('REFRESH')),
          ],
        ),
      ),
    );
  }
}
