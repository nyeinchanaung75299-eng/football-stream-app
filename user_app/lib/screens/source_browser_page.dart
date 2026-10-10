import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics_service.dart';
import '../backend_endpoint.dart';
import '../network_endpoints.dart';
import '../native_player.dart';
import 'home_page.dart';
import '../live_feed_controller.dart';
import '../player_loading.dart';
import '../source_line_loader.dart';
import '../source_match_discovery.dart';
import '../widgets/premium_bottom_nav.dart';
import '../widgets/premium_match_card.dart';
import '../widgets/source_match_filters.dart';

class SourceBrowserPage extends StatefulWidget {
  const SourceBrowserPage({super.key, required this.source});
  final String source;

  @override
  State<SourceBrowserPage> createState() => _SourceBrowserPageState();
}

class _SourceBrowserPageState extends State<SourceBrowserPage> {
  static const _primary = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );
  static const _supabaseFunction =
      'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/soco-links';
  static const _sourceMirrorBase =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources';
  static const _rawSourceMirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/sources';

  // Vercel is a live API route. The old mirror/cache fallback remains opt-in
  // for a special build with ENABLE_NO_VPN_FALLBACK=1.
  static final bool _enableNoVpnFallback =
      const String.fromEnvironment(
        'ENABLE_NO_VPN_FALLBACK',
        defaultValue: '0',
      ).trim() ==
      '1';

  late final LiveFeedController<List<Map<String, dynamic>>> _feed;
  Timer? _sourceRefreshTimer;
  bool _openingPlayer = false;
  int _sourceGeneration = 0;
  SourceLineLoader? _sourceOperation;
  final _searchController = TextEditingController();
  String _query = '';
  String? _league;
  bool _todayOnly = false;

  String get source => widget.source.toLowerCase();
  String get title => switch (source) {
        'yyzb' => 'YYZB',
        'fawa' => 'Fawa',
        'cola' => 'ColaTV',
        _ => 'Soco',
      };
  int get navIndex => switch (source) {
        'soco' => 1,
        'yyzb' => 2,
        'fawa' => 3,
        'cola' => 4,
        _ => 1,
      };
  List<String> get bases => publicApiBases(
        primary: _primary, preferVercel: usesVercelBackend);

  @override
  void initState() {
    super.initState();
    _todayOnly = source == 'yyzb';
    _feed = LiveFeedController(_loadMatches);
    unawaited(_feed.refresh());
    _sourceRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refresh(silent: true)),
    );
  }

  @override
  void didUpdateWidget(covariant SourceBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _cancelSourceOperation();
      _query = '';
      _searchController.clear();
      _league = null;
      _todayOnly = source == 'yyzb';
      unawaited(_feed.refresh());
    }
  }

  void _cancelSourceOperation() {
    _sourceGeneration++;
    _sourceOperation?.cancel();
    _openingPlayer = false;
  }

  @override
  void dispose() {
    _cancelSourceOperation();
    _searchController.dispose();
    _sourceRefreshTimer?.cancel();
    _feed.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _hedged(
    List<Future<List<Map<String, dynamic>>> Function()> jobs,
  ) {
    final c = Completer<List<Map<String, dynamic>>>();
    var next = 0;
    var running = 0;
    List<Map<String, dynamic>>? emptyFallback;
    Object? error;
    StackTrace? stack;
    Timer? timer;

    void finishIfDone() {
      if (c.isCompleted || next < jobs.length || running > 0) return;
      timer?.cancel();
      if (emptyFallback != null) {
        c.complete(emptyFallback!);
      } else if (error != null) {
        c.completeError(error!, stack);
      } else {
        c.complete(const <Map<String, dynamic>>[]);
      }
    }

    void start() {
      if (c.isCompleted || next >= jobs.length) {
        finishIfDone();
        return;
      }
      final job = jobs[next++];
      running++;
      job().then((value) {
        running--;
        if (c.isCompleted) return;
        if (value.isNotEmpty) {
          timer?.cancel();
          c.complete(value);
          return;
        }

        // An empty source is still a valid last-resort result, but do not let
        // it win the hedge while another VPN-off/live fallback may have rows.
        emptyFallback ??= value;
        if (next < jobs.length) start();
        finishIfDone();
      }).catchError((Object e, StackTrace s) {
        running--;
        error = e;
        stack = s;
        if (!c.isCompleted && next < jobs.length) start();
        finishIfDone();
      });
    }

    start();
    timer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (c.isCompleted) {
        t.cancel();
        return;
      }
      if (next < jobs.length) start();
      if (next >= jobs.length) {
        t.cancel();
        finishIfDone();
      }
    });
    return c.future;
  }

  static const _staleAfter = Duration(hours: 4);

  DateTime? _kickoff(Map<String, dynamic> m) {
    final parsed = DateTime.tryParse(m['match_time']?.toString() ?? '');
    return parsed?.toUtc();
  }

  bool _stale(Map<String, dynamic> m) {
    final kickoff = _kickoff(m);
    if (kickoff == null) return false;
    return DateTime.now().toUtc().difference(kickoff) > _staleAfter;
  }

  Future<List<Map<String, dynamic>>> _authoritativeHedged(
    List<Future<List<Map<String, dynamic>>> Function()> jobs,
  ) {
    final c = Completer<List<Map<String, dynamic>>>();
    var next = 0;
    var running = 0;
    Object? error;
    StackTrace? stack;
    Timer? timer;

    void finishIfDone() {
      if (c.isCompleted || next < jobs.length || running > 0) return;
      timer?.cancel();
      if (error != null) {
        c.completeError(error!, stack);
      } else {
        c.completeError(Exception('No authoritative source endpoint succeeded.'));
      }
    }

    void start() {
      if (c.isCompleted || next >= jobs.length) {
        finishIfDone();
        return;
      }
      final job = jobs[next++];
      running++;
      job().then((value) {
        running--;
        if (c.isCompleted) return;
        // A valid empty live response is authoritative: do not resurrect
        // disappeared matches from a stale mirror.
        timer?.cancel();
        c.complete(value);
      }).catchError((Object e, StackTrace s) {
        running--;
        error = e;
        stack = s;
        if (!c.isCompleted && next < jobs.length) start();
        finishIfDone();
      });
    }

    if (jobs.isEmpty) {
      return Future.error(Exception('No authoritative source endpoint configured.'));
    }

    start();
    timer = Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (c.isCompleted) {
        t.cancel();
        return;
      }
      if (next < jobs.length) start();
      if (next >= jobs.length) {
        t.cancel();
        finishIfDone();
      }
    });
    return c.future;
  }

  bool _live(Map<String, dynamic> m) {
    if (_stale(m)) return false;
    if (m['is_live'] == true) return true;

    // Soco's numeric status/hot fields are availability/featured flags, not a
    // trustworthy match clock. Only explicit live-state text may mark a card
    // LIVE; otherwise show the provider kickoff time.
    for (final value in [m['match_status'], m['status']]) {
      final status = value?.toString().trim().toUpperCase() ?? '';
      if (const {'LIVE', 'INPLAY', 'IN_PLAY', '1H', '2H', 'HT'}
          .contains(status)) {
        return true;
      }
    }
    return false;
  }

  void _sortRows(List<Map<String, dynamic>> rows) =>
      rows.sort((a, b) => compareSourceMatches(a, b, isLive: _live));

  void _clearFilters() => setState(() {
        _query = '';
        _searchController.clear();
        _league = null;
        _todayOnly = false;
      });

  String _matchName(Map<String, dynamic> m) =>
      (m['home_team'] ?? 'Home').toString() +
      ' vs ' +
      (m['away_team'] ?? 'Away').toString();

  Future<List<Map<String, dynamic>>> _loadFrom(String base) async {
    final response = await http
        .get(
          Uri.parse(base + '/sources/' + source + '/matches').replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 9));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Source API HTTP ' + response.statusCode.toString());
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List) throw const FormatException('Invalid source matches.');
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .where((row) => !_stale(row))
        .toList();
    _sortRows(rows);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadFromMirror([
    String base = _sourceMirrorBase,
  ]) async {
    final response = await http
        .get(
          Uri.parse('$base/$source.json').replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'GitHub source mirror HTTP ' + response.statusCode.toString(),
      );
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List) {
      throw const FormatException('Invalid GitHub source mirror.');
    }
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .where((row) => !_stale(row))
        .toList();
    _sortRows(rows);
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadFromSupabase() async {
    final response = await http
        .get(
          Uri.parse(_supabaseFunction).replace(
            queryParameters: {
              'viewer_public': '1',
              'action': 'matches',
              'source': source,
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 9));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Direct source fallback HTTP ' + response.statusCode.toString(),
      );
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List) throw const FormatException('Invalid direct source list.');
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .where((row) => !_stale(row))
        .toList();
    _sortRows(rows);
    return rows;
  }

  String get _cacheKey => 'viewer_source_cache_v1_' + source;

  Future<void> _saveLastGood(List<Map<String, dynamic>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'fetched_at': DateTime.now().toUtc().toIso8601String(),
          'matches': rows,
        }),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _loadLastGood() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['matches'] is! List) return null;
      final fetched = DateTime.tryParse(
        decoded['fetched_at']?.toString() ?? '',
      );
      if (fetched == null ||
          DateTime.now().toUtc().difference(fetched.toUtc()) >
              const Duration(minutes: 20)) {
        return null;
      }
      return (decoded['matches'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadMatches() async {
    if (!_enableNoVpnFallback) {
      if (bases.isEmpty) {
        throw StateError('No live source API is configured.');
      }
      return _authoritativeHedged(
        bases.map<Future<List<Map<String, dynamic>>> Function()>(
          (base) => () => _loadFrom(base),
        ).toList(),
      );
    }

    Object? authoritativeError;
    StackTrace? authoritativeStack;

    final workerJobs =
        bases.map<Future<List<Map<String, dynamic>>> Function()>(
          (base) => () => _loadFrom(base),
        ).toList();

    try {
      // Live source endpoints are authoritative. A successful empty response
      // means the provider currently has no matches, so return [] rather than
      // reviving rows from an older GitHub mirror.
      final rows = await _authoritativeHedged([
        ...workerJobs,
        () => _loadFromSupabase(),
      ]);
      unawaited(_saveLastGood(rows));
      return rows;
    } catch (error, stack) {
      authoritativeError = error;
      authoritativeStack = stack;
    }

    try {
      // Mirrors are connectivity fallbacks only (VPN/DNS/backend outage).
      final rows = await _hedged([
        () => _loadFromMirror(),
        () => _loadFromMirror(_rawSourceMirrorBase),
      ]);
      unawaited(_saveLastGood(rows));
      return rows;
    } catch (_) {
      final cached = await _loadLastGood();
      if (cached != null) return cached;
      Error.throwWithStackTrace(
        authoritativeError,
        authoritativeStack,
      );
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    await _feed.refresh();
    if (!silent && mounted && _feed.hasData && _feed.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not refresh. Showing the previous results.')),
      );
    }
  }

  List<Map<String, dynamic>> _anchors(Map<String, dynamic> m) =>
      sourceMatchAnchors(m, source);

  Future<List<Map<String, dynamic>>> _anchorFrom(
    String base,
    Map<String, dynamic> m,
    Map<String, dynamic> anchor, {
    String? sourceName,
  }) async {
    final response = await http
        .post(
          Uri.parse(base + '/sources/' + (sourceName ?? source) + '/streams'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'skip_probe': true,
            'room_num':
                anchor['room_num'] ?? m['source_id'] ?? m['schedule_id'],
            'schedule_id': m['schedule_id'] ?? m['source_id'],
            'source_id': m['source_id'],
            'page_url': anchor['page_url'] ?? m['page_url'],
            'anchor_name':
                anchor['nick_name'] ?? anchor['name'] ?? anchor['room_num'],
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Stream API HTTP ' + response.statusCode.toString());
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['streams'] : null;
    if (raw is! List) throw const FormatException('Invalid source streams.');
    return raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .where((x) => (x['stream_url']?.toString() ?? '').trim().isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _anchorFromSupabase(
    Map<String, dynamic> m,
    Map<String, dynamic> anchor, {
    String? sourceName,
  }) async {
    final provider = sourceName ?? source;
    final response = await http
        .get(
          Uri.parse(_supabaseFunction).replace(
            queryParameters: {
              'viewer_public': '1',
              'skip_probe': '1',
              'action': 'streams',
              'source': provider,
              'room_num':
                  (anchor['room_num'] ?? m['source_id'] ?? m['schedule_id'] ?? '')
                      .toString(),
              'schedule_id':
                  (m['schedule_id'] ?? m['source_id'] ?? '').toString(),
              'source_id': (m['source_id'] ?? '').toString(),
              'page_url':
                  (anchor['page_url'] ?? m['page_url'] ?? '').toString(),
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Direct stream fallback HTTP ' + response.statusCode.toString(),
      );
    }
    final decoded = jsonDecode(response.body);
    final raw = decoded is Map ? decoded['lines'] : null;
    if (raw is! List) throw const FormatException('Invalid direct streams.');
    final name =
        (anchor['nick_name'] ?? anchor['name'] ?? anchor['room_num'] ?? '')
            .toString()
            .trim();
    final room =
        (anchor['room_num'] ?? m['source_id'] ?? m['schedule_id'] ?? '')
            .toString();
    final schedule =
        (m['schedule_id'] ?? m['source_id'] ?? 'match').toString();

    return raw.asMap().entries.map((entry) {
      final row = Map<String, dynamic>.from(entry.value as Map);
      final url = (row['url'] ?? row['stream_url'] ?? '').toString().trim();
      final rawLabel = (row['label'] ??
              row['resolution'] ??
              ('Line ' + (entry.key + 1).toString()))
          .toString();
      return <String, dynamic>{
        'id': provider +
            ':' +
            schedule +
            ':' +
            room +
            ':' +
            entry.key.toString(),
        'label': name.isEmpty ? rawLabel : name + ' • ' + rawLabel,
        'resolution': row['resolution'],
        'stream_type': row['stream_type'] ?? 'auto',
        'stream_url': url,
        'referer': row['referer'],
        'origin': row['origin'],
        'key_id': null,
        'key_data': null,
        'is_active': true,
        'priority': row['priority'] ?? 100,
        'health_status': row['health_status'] ?? 'unknown',
      };
    }).where((x) => (x['stream_url']?.toString() ?? '').isNotEmpty).toList();
  }

  Future<List<Map<String, dynamic>>> _anchor(
    Map<String, dynamic> m,
    Map<String, dynamic> anchor,
  ) {
    final provider = source;
    if (!_enableNoVpnFallback) {
      if (bases.isEmpty) {
        return Future.error(StateError('No live source API is configured.'));
      }
      return _hedged(bases.map<Future<List<Map<String, dynamic>>> Function()>(
        (base) => () => _anchorFrom(base, m, anchor, sourceName: provider),
      ).toList());
    }

    return _hedged(
      [
        if (bases.isNotEmpty)
          () => _anchorFrom(bases.first, m, anchor, sourceName: provider),
        () => _anchorFromSupabase(m, anchor, sourceName: provider),
        ...bases.skip(1).map<Future<List<Map<String, dynamic>>> Function()>(
          (base) => () => _anchorFrom(base, m, anchor, sourceName: provider),
        ),
      ],
    );
  }

  int _compareLines(Map<String, dynamic> a, Map<String, dynamic> b) {
    int rank(Map<String, dynamic> x) {
      final t = (x['stream_type'] ?? 'auto').toString().toLowerCase();
      if (t == 'hls' || t == 'm3u8') return 0;
      // Web FLV can begin without waiting for a DASH manifest/segment set.
      if (kIsWeb && t == 'flv') return 1;
      if (t == 'dash' || t == 'mpd') return 2;
      if (t == 'mp4') return 3;
      if (t == 'auto') return 4;
      if (t == 'flv') return 5;
      return 6;
    }

    int healthRank(Map<String, dynamic> x) {
      return switch ((x['health_status'] ?? 'unknown')
          .toString()
          .toLowerCase()) {
        'healthy' => 0,
        'unknown' => 1,
        'slow' => 2,
        'failed' => 3,
        _ => 2,
      };
    }

    final health = healthRank(a).compareTo(healthRank(b));
    if (health != 0) return health;
    final format = rank(a).compareTo(rank(b));
    if (format != 0) return format;
    return ((a['priority'] as num?)?.toInt() ?? 100).compareTo(
      (b['priority'] as num?)?.toInt() ?? 100,
    );
  }

  SourceLineLoader _streams(Map<String, dynamic> match) => SourceLineLoader(
    anchors: _anchors(match)
        .map<Future<SourceLines> Function()>(
          (anchor) =>
              () => _anchor(match, anchor),
        )
        .toList(),
    compare: _compareLines,
  );

  List<Map<String, dynamic>> _playerSources(SourceLines rows) => rows
      .map(
        (x) => <String, dynamic>{
          'id': x['id']?.toString(),
          'label': (x['label'] ?? x['resolution'] ?? 'Server').toString(),
          'streamType': (x['stream_type'] ?? 'auto').toString(),
          'url': (x['stream_url'] ?? '').toString(),
          'referer': (x['referer'] ?? '').toString(),
          'origin': (x['origin'] ?? '').toString(),
          'keyId': (x['key_id'] ?? '').toString(),
          'keyData': (x['key_data'] ?? '').toString(),
          'resolution': (x['resolution'] ?? '').toString(),
          'healthStatus': (x['health_status'] ?? 'unknown').toString(),
          'priority': (x['priority'] as num?)?.toInt() ?? 100,
        },
      )
      .toList();

  Future<void> _watch(Map<String, dynamic> m) async {
    if (_openingPlayer || !mounted) return;
    _cancelSourceOperation();
    _openingPlayer = true;
    final generation = _sourceGeneration;
    try {
      await _openSourcePlayer(m);
    } finally {
      if (generation == _sourceGeneration) _openingPlayer = false;
    }
  }

  Future<void> _openSourcePlayer(Map<String, dynamic> m) async {
    if (_anchors(m).isEmpty) return;
    final generation = _sourceGeneration;
    final selectedSource = source;
    final operation = _streams(m);
    _sourceOperation = operation;
    final resolution = Stopwatch()..start();
    final sessionId = '$selectedSource-$generation-${UniqueKey()}';
    var playerOpened = false;
    var publishedCount = 0;

    bool current() =>
        mounted &&
        generation == _sourceGeneration &&
        identical(_sourceOperation, operation) &&
        !operation.cancelled;

    void publishBackups() {
      if (!current() || !playerOpened || operation.rows.length <= publishedCount) {
        return;
      }
      publishedCount = operation.rows.length;
      unawaited(
        NativePlayer.updateSources(
          sources: _playerSources(operation.rows),
          sessionId: sessionId,
        ).catchError((Object _) {}),
      );
    }

    operation.addListener(publishBackups);
    try {
      final rows = await loadPlayerSources<SourceLines?>(context, () {
        operation.start();
        return operation.firstUsable;
      }, onCancelled: operation.cancel);
      resolution.stop();
      if (rows == null || !current()) return;
      final providerMatchId =
          (m['source_id'] ?? m['schedule_id'] ?? '').toString();
      final safeMatchId = RegExp(r'^[a-zA-Z0-9_-]{1,100}$')
              .hasMatch(providerMatchId)
          ? providerMatchId
          : 'unknown';
      unawaited(
        AnalyticsService.capture(
          'stream sources loaded',
          properties: {
            'source': selectedSource,
            'match_id': '$selectedSource:$safeMatchId',
            'resolution_ms': resolution.elapsedMilliseconds,
            'count': rows.length,
          },
        ),
      );
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No ' + title + ' stream is available now.')),
        );
        return;
      }

      final picked = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => AnimatedBuilder(
          animation: operation,
          builder: (_, __) {
            final sources = _playerSources(operation.rows);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: sources.length <= 4 ? .52 : .72,
              minChildSize: .38,
              maxChildSize: .90,
              builder: (_, controller) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title + ' • ' + _matchName(m),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          sources.length.toString() +
                              (operation.loading ? ' lines…' : ' lines'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.all(14),
                      itemCount: sources.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final x = sources[i];
                        final label = x['label']?.toString().trim() ?? '';
                        final type =
                            x['streamType']?.toString().toUpperCase() ?? 'AUTO';
                        final quality =
                            x['resolution']?.toString().trim() ?? '';
                        final health =
                            x['healthStatus']?.toString().toLowerCase() ??
                            'unknown';
                        final healthLabel = switch (health) {
                          'healthy' => 'READY',
                          'slow' => 'SLOW',
                          'failed' => 'OFFLINE',
                          'dead' => 'OFFLINE',
                          _ => 'UNKNOWN',
                        };
                        final healthIcon = switch (health) {
                          'healthy' => Icons.check_circle_rounded,
                          'slow' => Icons.speed_rounded,
                          'failed' => Icons.cloud_off_rounded,
                          'dead' => Icons.cloud_off_rounded,
                          _ => Icons.help_outline_rounded,
                        };
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(sheet).colorScheme.outlineVariant,
                            ),
                          ),
                          leading: const Icon(Icons.live_tv_rounded),
                          title: Text(
                            label.isEmpty
                                ? 'Line ' + (i + 1).toString()
                                : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              quality,
                              type,
                              healthLabel,
                            ].where((x) => x.isNotEmpty).join(' • '),
                          ),
                          trailing: Icon(
                            healthIcon,
                            color: health == 'healthy'
                                ? Colors.green
                                : health == 'slow'
                                ? Colors.orange
                                : (health == 'failed' || health == 'dead')
                                ? Colors.redAccent
                                : null,
                          ),
                          onTap: () => Navigator.pop(sheet, i),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      if (picked == null || !current()) return;
      publishedCount = operation.rows.length;
      await NativePlayer.open(
        context: context,
        sources: _playerSources(operation.rows),
        selectedIndex: picked,
        title: _matchName(m),
        matchId:
            selectedSource +
            ':' +
            (m['source_id'] ?? m['schedule_id'] ?? '').toString(),
        sessionId: sessionId,
      );
      playerOpened = true;
      publishBackups();
      if (generation == _sourceGeneration) _openingPlayer = false;
      // Opening returns immediately on Web/Android. Keep forwarding late
      // anchors until they settle; the player rejects a closed/stale session.
      await operation.settled;
      publishBackups();
    } finally {
      operation.removeListener(publishBackups);
      operation.dispose();
      if (identical(_sourceOperation, operation)) _sourceOperation = null;
    }
  }

  void _select(int index) {
    if (index == navIndex) {
      unawaited(_refresh());
      return;
    }
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (index == 5) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const HomePage(ncaView: true),
        ),
      );
      return;
    }
    final next = switch (index) {
      2 => 'yyzb',
      3 => 'fawa',
      4 => 'cola',
      _ => 'soco',
    };
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SourceBrowserPage(source: next),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 12,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -.25,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh source',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 3),
        ],
      ),
      body: AnimatedBuilder(
        animation: _feed,
        builder: (_, _) {
          if (_feed.loading && !_feed.hasData) {
            return _SourceLoading(title: title);
          }
          if (_feed.error != null && !_feed.hasData) {
            return _StateView(
              title: title + ' unavailable',
              text: source == 'fawa'
                  ? 'Fawa website or source API is unreachable. Refresh later.'
                  : 'Connect VPN, then refresh.',
              onRefresh: _refresh,
            );
          }

          final allMatches = _feed.data ?? const <Map<String, dynamic>>[];
          if (allMatches.isEmpty) {
            return _StateView(
              title: 'No ' + title + ' matches',
              text: 'No football matches are available from this source now.',
              onRefresh: _refresh,
            );
          }

          final matches = filterSourceMatches(
            allMatches,
            todayOnly: _todayOnly,
            query: _query,
            league: _league,
          );
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: SourceMatchFilters(
                    controller: _searchController,
                    todayOnly: _todayOnly,
                    league: _league,
                    leagues: sourceMatchLeagues(allMatches),
                    visibleCount: matches.length,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onTodayChanged: (value) => setState(() => _todayOnly = value),
                    onLeagueChanged: (value) => setState(() => _league = value),
                  ),
                ),
                if (matches.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No matches for these filters'),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Clear filters'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
                    sliver: SliverList.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final m = matches[index];
                        final live = _live(m);
                        final anchors = _anchors(m);
                        final ready = anchors.isNotEmpty;
                        final time = DateTime.tryParse(
                          m['match_time']?.toString() ?? '',
                        )?.toLocal();

                        return PremiumMatchCard(
                          league: (m['league'] ?? 'Football').toString(),
                          homeName: (m['home_team'] ?? 'Home').toString(),
                          awayName: (m['away_team'] ?? 'Away').toString(),
                          homeLogo:
                              (m['home_logo'] ?? m['home_logo_url'])?.toString(),
                          awayLogo:
                              (m['away_logo'] ?? m['away_logo_url'])?.toString(),
                          kickoff: time,
                          isLive: live,
                          canWatch: ready,
                          actionLabel: ready
                              ? (anchors.length > 1
                                  ? 'WATCH  •  ' +
                                      anchors.length.toString() +
                                      ' SOURCES'
                                  : 'WATCH')
                              : 'NOT READY',
                          onWatch: () => _watch(m),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: PremiumBottomNav(
        selectedIndex: navIndex,
        onSelected: _select,
      ),
    );
  }
}

class _SourceLoading extends StatelessWidget {
  const _SourceLoading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .24),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading ' + title + '…',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.title,
    required this.text,
    required this.onRefresh,
  });

  final String title;
  final String text;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.sports_soccer_outlined,
                  size: 29,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => onRefresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REFRESH'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
