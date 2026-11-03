import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../analytics_service.dart';
import '../network_endpoints.dart';
import '../playback_routes.dart';
import '../native_player.dart';
import 'channels_page.dart';
import '../live_feed_controller.dart';
import '../player_loading.dart';
import '../source_line_loader.dart';
import '../source_match_discovery.dart';
import '../football_english.dart';
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
  DateTime? _lastSourcePoll;
  bool _openingPlayer = false;
  int _sourceGeneration = 0;
  SourceLineLoader? _sourceOperation;
  final _searchController = TextEditingController();
  String _query = '';
  String? _league;
  bool _todayOnly = false;
  // YYZB is presented as its watchable football room catalogue, not as its
  // full score database. The state remains for the shared filter component,
  // but Viewer never exposes an all-schedule toggle for YYZB.

  String get source => widget.source.toLowerCase();
  String get title => switch (source) {
    'yyzb' => 'YYZB',
    'fawa' => 'Fawa',
    'cola' => 'ColaTV',
    'xoilac' => 'Xoilac',
    'camel' => 'Camel1',
    _ => 'Soco',
  };
  int get navIndex => switch (source) {
    'soco' => 1,
    'yyzb' => 2,
    'fawa' => 3,
    'cola' => 4,
    'xoilac' => 6,
    'camel' => 7,
    _ => 1,
  };
  List<Future<List<Map<String, dynamic>>> Function()> _apiJobs(
    Future<List<Map<String, dynamic>>> Function(String) load,
  ) {
    var winnerRecorded = false;
    return bases
        .map<Future<List<Map<String, dynamic>>> Function()>((base) => () async {
              final rows = await load(base);
              if (!winnerRecorded) {
                winnerRecorded = true;
                rememberVerifiedPublicApiBase(base);
              }
              return rows;
            })
        .toList();
  }

  List<String> get bases {
    final routes = publicApiBases(
      primary: _primary,
      // Public source routing is independent of the selected Auth relay.
      preferVercel: false,
    );
    return routes;
  }

  @override
  void initState() {
    super.initState();
    // YYZB evening rooms can cross local midnight. Its website lists those
    // rooms together, so a local-calendar Today filter must not hide them.
    _todayOnly = false;
    _feed = LiveFeedController(_loadMatches);
    unawaited(_feed.refresh());
    _sourceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (mounted &&
          !_openingPlayer &&
          (state == null || state == AppLifecycleState.resumed) &&
          ModalRoute.of(context)?.isCurrent != false) {
        final live = _feed.data?.any(_live) ?? false;
        final now = DateTime.now();
        if (!live && _lastSourcePoll != null &&
            now.difference(_lastSourcePoll!) < const Duration(minutes: 2)) {
          return;
        }
        _lastSourcePoll = now;
        unawaited(_refresh(silent: true));
      }
    });
  }

  @override
  void didUpdateWidget(covariant SourceBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _lastSourcePoll = null;
      _cancelSourceOperation();
      _query = '';
      _searchController.clear();
      _league = null;
      _todayOnly = false;
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
      job()
          .then((value) {
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
          })
          .catchError((Object e, StackTrace s) {
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

  // Keep the established Soco/YYZB recent-match cutoff. All dates means
  // all currently available dates, never an archive of completed fixtures.
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
        c.completeError(
          Exception('No authoritative source endpoint succeeded.'),
        );
      }
    }

    void start() {
      if (c.isCompleted || next >= jobs.length) {
        finishIfDone();
        return;
      }
      final job = jobs[next++];
      running++;
      job()
          .then((value) {
            running--;
            if (c.isCompleted) return;
            // A valid empty live response is authoritative: do not resurrect
            // disappeared matches from a stale mirror.
            timer?.cancel();
            c.complete(value);
          })
          .catchError((Object e, StackTrace s) {
            running--;
            error = e;
            stack = s;
            if (!c.isCompleted && next < jobs.length) start();
            finishIfDone();
          });
    }

    if (jobs.isEmpty) {
      return Future.error(
        Exception('No authoritative source endpoint configured.'),
      );
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
      if (const {
        'LIVE',
        'INPLAY',
        'IN_PLAY',
        '1H',
        '2H',
        'HT',
      }.contains(status)) {
        return true;
      }
    }
    return false;
  }

  void _sortRows(List<Map<String, dynamic>> rows) => rows.sort(
    (a, b) => compareSourceMatches(
      a,
      b,
      isLive: _live,
      majorCompetitionFirst: source == 'yyzb',
    ),
  );

  void _clearFilters() => setState(() {
    _query = '';
    _searchController.clear();
    _league = null;
    _todayOnly = false;
  });

  String _matchName(Map<String, dynamic> m) => m['kind'] == 'channel'
      ? (m['home_team'] ?? 'Sports channel').toString()
      : (m['home_team'] ?? 'Home').toString() +
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
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 9));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Source API HTTP ' + response.statusCode.toString());
    }
    final decoded = jsonDecode(response.body);
    if (source == 'soco' && decoded is Map && decoded['ok'] == false) {
      // An unavailable provider is not an authoritative empty schedule.
      throw const FormatException('Soco source temporarily unavailable.');
    }
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List) throw const FormatException('Invalid source matches.');
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .map((row) => englishSourceMatch(row, source))
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
    if (decoded is Map && decoded['ok'] == false) {
      // A failed Soco mirror sync must not masquerade as a successful empty
      // provider schedule. Allow other live routes and local last-good data.
      throw const FormatException('Source snapshot is unavailable.');
    }
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List) {
      throw const FormatException('Invalid GitHub source mirror.');
    }
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .map((row) => englishSourceMatch(row, source))
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
    if (source == 'soco' && decoded is Map && decoded['ok'] == false) {
      // An unavailable provider is not an authoritative empty schedule.
      throw const FormatException('Soco source temporarily unavailable.');
    }
    final raw = decoded is Map ? decoded['matches'] : null;
    if (raw is! List)
      throw const FormatException('Invalid direct source list.');
    final rows = raw
        .map((x) => Map<String, dynamic>.from(x as Map))
        .map((row) => englishSourceMatch(row, source))
        .where((row) => !_stale(row))
        .toList();
    _sortRows(rows);
    return rows;
  }

  String get _cacheKey => 'viewer_source_cache_v1_$source';

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
          .map((row) => englishSourceMatch(row, source))
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
      return _authoritativeHedged(_apiJobs(_loadFrom));
    }

    Object? authoritativeError;
    StackTrace? authoritativeStack;

    final workerJobs = bases
        .map<Future<List<Map<String, dynamic>>> Function()>(
          (base) =>
              () => _loadFrom(base),
