import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../analytics_service.dart';
import '../native_player.dart';
import 'soco_page.dart';
import 'network_diagnostics_page.dart';
import '../widgets/theme_mode_button.dart';
import '../app_update_service.dart';

class _MatchLoadResult {
  const _MatchLoadResult(this.rows, this.label);

  final List<Map<String, dynamic>> rows;
  final String? label;
}

class _StreamCacheEntry {
  const _StreamCacheEntry(this.rows, this.fetchedAt);

  final List<Map<String, dynamic>> rows;
  final DateTime fetchedAt;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _scoreRefresh;
  late Future<String> _versionLabel;
  late Future<String> _updateVersionLabel;
  final Map<String, _StreamCacheEntry> _streamLinkCache = {};
  final Map<String, Future<List<Map<String, dynamic>>>> _streamLinkInflight = {};

  static const _publicApiBase = String.fromEnvironment(
    'PUBLIC_API_BASE',
    defaultValue: 'https://football-api.nyeinchanaung.us.ci',
  );
  static const _publicApiBackup =
      'https://football-public-api.nyeinchanaung75299-eng.workers.dev';

  List<String> get _publicApiBases => <String>{
        _publicApiBase.trim().replaceAll(RegExp(r'/+$'), ''),
        _publicApiBackup,
      }.where((base) => base.isNotEmpty).toList();

  static const _mirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/matches.json';
  // On GitHub Pages, use the metadata JSON deployed beside the Flutter app.
  // Playback URLs are intentionally never published to GitHub.
  Uri _mirrorMatchesUri() =>
      kIsWeb ? Uri.base.resolve('matches.json') : Uri.parse(_mirrorBase);

  SupabaseClient? _supabaseClientOrNull() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<T> _hedged<T>(
    List<Future<T> Function()> attempts, {
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (attempts.isEmpty) {
      return Future<T>.error(StateError('No fallback source is configured.'));
    }

    final completer = Completer<T>();
    var nextIndex = 0;
    var running = 0;
    Object? lastError;
    StackTrace? lastStack;
    Timer? timer;

    void startNext() {
      if (completer.isCompleted || nextIndex >= attempts.length) return;

      final run = attempts[nextIndex++];
      running += 1;

      run().then((value) {
        if (!completer.isCompleted) {
          timer?.cancel();
          completer.complete(value);
        }
      }).catchError((Object error, StackTrace stackTrace) {
        running -= 1;
        lastError = error;
        lastStack = stackTrace;

        if (!completer.isCompleted && nextIndex < attempts.length) {
          startNext();
        } else if (
            !completer.isCompleted &&
            nextIndex >= attempts.length &&
            running == 0) {
          timer?.cancel();
          completer.completeError(
            lastError ?? StateError('All fallback sources failed.'),
            lastStack ?? StackTrace.current,
          );
        }
      });
    }

    startNext();

    if (attempts.length > 1) {
      timer = Timer.periodic(delay, (value) {
        if (completer.isCompleted || nextIndex >= attempts.length) {
          value.cancel();
          return;
        }
        startNext();
      });
    }

    return completer.future;
  }

  @override
  void initState() {
    super.initState();
    _future = loadMatches();
    _versionLabel = _loadVersionLabel();
    _updateVersionLabel = AppUpdateService.versionSummary();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppUpdateService.check(context);
    });
    final supabase = _supabaseClientOrNull();
    if (supabase != null) {
      _channel = supabase
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

    // Keep scores moving even on networks where Supabase Realtime is blocked.
    // The public Cloudflare feed is cached briefly, so a 60s silent refresh
    // gives the UI fresh server-side scores without user interaction.
    _scoreRefresh = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) refresh(silent: true);
    });
  }

  Future<String> _loadVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim().isEmpty ? '9.8.0' : info.version.trim();
      final build = info.buildNumber.trim();
      return build.isEmpty
          ? 'V$version • Auto live scores'
          : 'V$version • build $build • Auto live scores';
    } catch (_) {
      return 'V9.8 • Auto live scores';
    }
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

  List<Map<String, dynamic>> _mergeAvailability(
    List<Map<String, dynamic>> primary,
    List<Map<String, dynamic>> secondary,
  ) {
    final secondaryById = <String, Map<String, dynamic>>{
      for (final row in secondary)
        if ((row['id']?.toString() ?? '').isNotEmpty)
          row['id'].toString(): row,
    };

    for (final row in primary) {
      final id = row['id']?.toString() ?? '';
      final other = secondaryById[id];
      if (other == null) continue;

      final a = (row['stream_count'] as num?)?.toInt() ?? 0;
      final b = (other['stream_count'] as num?)?.toInt() ?? 0;
      if (b > a) row['stream_count'] = b;
    }

    return primary;
  }

  List<Map<String, dynamic>> _visibleMatches(
    List<Map<String, dynamic>> rows,
  ) {
    const finishedStatuses = {'FT', 'AET', 'PEN'};
    const grace = Duration(minutes: 8);
    final now = DateTime.now();
    const staleKickoffGrace = Duration(hours: 5);

    return rows.where((row) {
      final status =
          (row['status_short'] ?? '').toString().trim().toUpperCase();
      final finished =
          row['is_finished'] == true || finishedStatuses.contains(status);

      // When the score provider is unavailable, an old NS row can otherwise
      // stay visible forever in a fallback feed. Keep explicitly-live rows,
      // but hide non-live matches five hours after their scheduled kickoff.
      final kickoff = DateTime.tryParse(
        row['kickoff_at']?.toString() ?? '',
      )?.toLocal();
      if (row['is_live'] != true &&
          kickoff != null &&
          now.difference(kickoff) > staleKickoffGrace) {
        return false;
      }

      if (!finished) return true;

      final detectedText =
          row['last_score_sync_at']?.toString() ??
          row['updated_at']?.toString();
      final detectedAt = detectedText == null
          ? null
          : DateTime.tryParse(detectedText)?.toLocal();

      // If an older fallback feed has no finish timestamp, keep it until the
      // server-side cleanup removes it rather than hiding it too early.
      if (detectedAt == null) return true;
      return now.difference(detectedAt) < grace;
    }).toList();
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
        _visibleMatches(
          raw
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(),
        ),
      );
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiFrom(
    String base,
  ) async {
    final response = await http
        .get(
          Uri.parse('$base/matches').replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Public API returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['source']?.toString() == 'github') {
      // Do not let the Worker's emergency GitHub mirror beat a fresher direct
      // database response. The mirror is still used explicitly as last resort.
      throw const FormatException('Public API is using the backup mirror.');
    }

    return _decodeMatches(response.body);
  }

  Future<List<Map<String, dynamic>>> _loadPublicApi() {
    return _hedged(
      _publicApiBases
          .map<Future<List<Map<String, dynamic>>> Function()>(
            (base) => () => _loadPublicApiFrom(base),
          )
          .toList(),
      delay: const Duration(milliseconds: 400),
    );
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiStreamsFrom(
    String base,
    String matchId,
  ) async {
    final uri = Uri.parse(
      '$base/matches/${Uri.encodeComponent(matchId)}/streams',
    ).replace(
      queryParameters: {
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final response = await http
        .get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 4));

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

    final rows = raw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    if (decoded is Map<String, dynamic> &&
        decoded['blocked_streams'] is List) {
      final blocked = (decoded['blocked_streams'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .map((row) => <String, dynamic>{
                ...row,
                // A local non-playable sentinel keeps the option visible in
                // the chooser without exposing an upstream URL or key.
                'stream_url': 'blocked://keyed-dash',
              });
      rows.addAll(blocked);
    }

    if (rows.isEmpty) {
      throw const FormatException('No stream lines returned.');
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadPublicApiStreams(
    String matchId,
  ) {
    return _hedged(
      _publicApiBases
          .map<Future<List<Map<String, dynamic>>> Function()>(
            (base) => () => _loadPublicApiStreamsFrom(base, matchId),
          )
          .toList(),
      delay: const Duration(milliseconds: 120),
    );
  }

  Future<List<Map<String, dynamic>>> _resolveLinks(
    Map<String, dynamic> match,
  ) async {
    final matchId = match['id']?.toString().trim() ?? '';
    if (matchId.isEmpty) return const [];

    final cached = _streamLinkCache[matchId];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) <
            const Duration(seconds: 25) &&
        cached.rows.isNotEmpty) {
      return cached.rows;
    }

    final existing = _streamLinkInflight[matchId];
    if (existing != null) return existing;

    final request = () async {
      try {
        final rows = playableLinks(await _loadPublicApiStreams(matchId));
        if (rows.isNotEmpty) {
          _streamLinkCache[matchId] = _StreamCacheEntry(
            rows,
            DateTime.now(),
          );
        } else {
          _streamLinkCache.remove(matchId);
        }
        return rows;
      } catch (_) {
        _streamLinkCache.remove(matchId);
        return const <Map<String, dynamic>>[];
      } finally {
        _streamLinkInflight.remove(matchId);
      }
    }();

    _streamLinkInflight[matchId] = request;
    return request;
  }

  Future<void> _warmStreamLinks(
    List<Map<String, dynamic>> matches,
  ) async {
    final candidates = matches
        .where(
          (match) =>
              ((match['stream_count'] as num?)?.toInt() ?? 0) > 0 &&
              (match['id']?.toString().trim().isNotEmpty ?? false),
        )
        .take(6)
        .toList();

    if (candidates.isEmpty) return;
    await Future.wait(
      candidates.map(_resolveLinks),
      eagerError: false,
    );
  }

  Future<List<Map<String, dynamic>>> _loadMirror() async {
    // GitHub Pages is the reliable transport on restricted networks. Use a
    // short cache bucket so a VPN toggle/refresh cannot keep an old snapshot
    // around for a full browser cache lifetime.
    final bucket = DateTime.now().millisecondsSinceEpoch ~/ 15000;
    final uri = _mirrorMatchesUri().replace(
      queryParameters: {'v': bucket.toString()},
    );

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

    final rows = _decodeMatches(response.body);
    // The mirror contains metadata and a safe line count only. Keep that count
    // so WATCH remains available on restricted networks; actual playback URLs
    // are still resolved exclusively through the protected Cloudflare API.
    for (final row in rows) {
      row['stream_links'] = const <Map<String, dynamic>>[];
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseMatches() async {
    final client = _supabaseClientOrNull();
    if (client == null) {
      throw StateError('Supabase is unavailable on this network.');
    }

    // Complete this fallback only when its safe availability counts are ready.
    // If either query fails, another hedged source can still return a full feed.
    // The count view exposes no upstream URLs, headers, or playback keys.
    final data = await Future.wait<List<Map<String, dynamic>>>([
      client
          .from('matches')
          .select('''
            id,league,home_team,away_team,home_logo_url,away_logo_url,
            kickoff_at,is_live,sort_order,home_score,away_score,status_short,
            status_elapsed,is_finished,is_featured,publish_state,
            last_score_sync_at,updated_at
          ''')
          .eq('is_active', true)
          .eq('publish_state', 'published')
          .eq('is_featured', true)
          .order('kickoff_at')
          .order('sort_order')
          .timeout(const Duration(seconds: 5)),
      client
          .from('match_stream_counts')
          .select('match_id,stream_count')
          .timeout(const Duration(seconds: 5)),
    ]);

    final rows = List<Map<String, dynamic>>.from(data[0]);
    for (final row in rows) {
      row['stream_count'] = 0;
      row['stream_links'] = const <Map<String, dynamic>>[];
    }
    final counts = data[1]
        .map((row) => <String, dynamic>{
              'id': row['match_id'],
              'stream_count': (row['stream_count'] as num?)?.toInt() ?? 0,
            })
        .toList();
    return _sortMatchesChronologically(
      _visibleMatches(_mergeAvailability(rows, counts)),
    );
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final started = DateTime.now();

    // Cloudflare and direct Supabase are authoritative. Race those first.
    // Only fall back to GitHub after both fail, otherwise an older mirror can
    // win the race and resurrect deleted matches or stale LIVE state.
    final authoritative = <Future<_MatchLoadResult> Function()>[
      () async => _MatchLoadResult(
            await _loadPublicApi(),
            'Fast public API',
          ),
    ];

    if (_supabaseClientOrNull() != null) {
      authoritative.add(
        () async => _MatchLoadResult(
              await _loadSupabaseMatches(),
              'Direct database',
            ),
      );
    }

    _MatchLoadResult result;
    try {
      result = await _hedged(
        authoritative,
        delay: const Duration(milliseconds: 500),
      );
    } catch (_) {
      result = _MatchLoadResult(
        await _loadMirror(),
        'Backup feed',
      );
    }

    unawaited(
      AnalyticsService.capture(
        'match feed loaded',
        properties: {
          'source': result.label ?? 'unknown',
          'match_count': result.rows.length,
          'latency_ms': DateTime.now().difference(started).inMilliseconds,
        },
      ),
    );

    unawaited(_warmStreamLinks(result.rows));
    return result.rows;
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
    final matchId = match['id']?.toString() ?? '';
    unawaited(AnalyticsService.capture(
      'watch tapped',
      properties: {
        'match_id': matchId,
        'league': (match['league'] ?? '').toString(),
        'is_live': match['is_live'] == true,
        'advertised_lines': (match['stream_count'] as num?)?.toInt() ?? 0,
      },
    ));

    final links = await _resolveLinks(match);
    if (links.isEmpty) {
      await AnalyticsService.capture(
        'stream unavailable',
        properties: {
          'match_id': matchId,
          'reason': 'protected_api_returned_no_lines',
          'advertised_lines': (match['stream_count'] as num?)?.toInt() ?? 0,
        },
      );
      if (!mounted) return;
      final advertised =
          (match['stream_count'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            advertised > 0
                ? 'Could not load the $advertised configured line(s). '
                    'Please tap WATCH again in a moment.'
                : 'Stream is not available yet.',
          ),
        ),
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
              'resolution': (x['resolution'] ?? '').toString(),
              'healthStatus': (x['health_status'] ?? 'unknown').toString(),
              'priority': (x['priority'] as num?)?.toInt() ?? 100,
              'blockedReason': (x['blocked_reason'] ?? '').toString(),
              'viewerMessage': (x['viewer_message'] ?? '').toString(),
            })
        .where((x) => (x['url'] as String).trim().isNotEmpty)
        .toList();

    if (nativeSources.isEmpty) {
      await AnalyticsService.capture(
        'stream unavailable',
        properties: {
          'match_id': matchId,
          'reason': 'no_native_sources',
          'resolved_lines': links.length,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This match currently has no native stream.')),
      );
      return;
    }

    var selectedIndex = 0;

    {
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
                                'Best available lines are shown first',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
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
                        final rawLabel =
                            (source['label'] ?? '').toString().trim();
                        final label = rawLabel.isEmpty
                            ? 'Line ${index + 1}'
                            : rawLabel;
                        final type =
                            (source['streamType'] ?? 'auto')
                                .toString()
                                .toLowerCase();
                        final resolution =
                            (source['resolution'] ?? '').toString().trim();
                        final health =
                            (source['healthStatus'] ?? 'unknown')
                                .toString()
                                .toLowerCase();
                        final blocked =
                            (source['blockedReason'] ?? '')
                                .toString()
                                .trim()
                                .isNotEmpty;
                        final hasKey =
                            (source['keyId']?.toString().trim().isNotEmpty ??
                                    false) &&
                                (source['keyData']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ??
                                    false);

                        String detail;
                        IconData icon;
                        if (blocked) {
                          detail = 'KEYED DASH • Viewer blocked • add HLS/non-DRM backup';
                          icon = Icons.lock_rounded;
                        } else if (type == 'hls' || type == 'm3u8') {
                          detail = 'Recommended • iPhone & Android';
                          icon = Icons.workspace_premium_rounded;
                        } else if (type == 'dash' || type == 'mpd') {
                          detail = hasKey
                              ? 'DASH • Adaptive • ClearKey'
                              : 'DASH • Adaptive quality';
                          icon = Icons.high_quality_rounded;
                        } else if (type == 'mp4') {
                          detail = 'Direct video • High compatibility';
                          icon = Icons.play_circle_fill_rounded;
                        } else if (type == 'flv') {
                          detail = 'Legacy live • Android preferred';
                          icon = Icons.live_tv_rounded;
                        } else {
                          detail = 'Auto • Direct stream';
                          icon = Icons.auto_awesome_rounded;
                        }

                        if (resolution.isNotEmpty &&
                            !label.toLowerCase().contains(
                                  resolution.toLowerCase(),
                                )) {
                          detail = '$resolution • $detail';
                        }

                        final statusText = blocked
                            ? 'BLOCKED'
                            : switch (health) {
                                'healthy' => 'READY',
                                'slow' => 'SLOW',
                                'failed' => 'CHECK',
                                _ => 'AUTO',
                              };
                        final statusColor = blocked
                            ? colors.error
                            : switch (health) {
                                'healthy' => colors.primary,
                                'slow' => Colors.orange,
                                'failed' => colors.error,
                                _ => colors.onSurfaceVariant,
                              };

                        return Material(
                          color: colors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: colors.outlineVariant
                                  .withValues(alpha: .55),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: blocked
                                ? null
                                : () => Navigator.pop(sheetContext, index),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: colors.primaryContainer
                                          .withValues(alpha: .72),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      icon,
                                      color: colors.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                label,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor
                                                    .withValues(alpha: .10),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: .5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          detail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    color: colors.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
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

    final selectedSource = nativeSources[selectedIndex];
    unawaited(AnalyticsService.capture(
      'stream selected',
      properties: {
        'match_id': matchId,
        'line_count': nativeSources.length,
        'selected_index': selectedIndex,
        'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
        'resolution': (selectedSource['resolution'] ?? '').toString(),
        'health_status':
            (selectedSource['healthStatus'] ?? 'unknown').toString(),
      },
    ));

    try {
      if (!mounted) return;
      await NativePlayer.open(
        context: context,
        sources: nativeSources,
        selectedIndex: selectedIndex,
        title: '${match['home_team']} vs ${match['away_team']}',
        matchId: matchId,
      );
      await AnalyticsService.capture(
        'player opened',
        properties: {
          'match_id': matchId,
          'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
        },
      );
    } catch (_) {
      await AnalyticsService.capture(
        'player open failed',
        properties: {
          'match_id': matchId,
          'stream_type': (selectedSource['streamType'] ?? 'auto').toString(),
        },
      );
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NCA',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FutureBuilder<String>(
                          future: _versionLabel,
                          builder: (context, snapshot) => Text(
                            snapshot.data ?? 'V9.8 • Auto live scores',
                            style: const TextStyle(fontSize: 12.5),
                          ),
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
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text(
                  'Check for updates',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: FutureBuilder<String>(
                  future: _updateVersionLabel,
                  builder: (context, snapshot) => Text(
                    snapshot.data ??
                        'Check and install the latest NCA APK',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  AppUpdateService.check(context, force: true);
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
    _scoreRefresh?.cancel();
    final c = _channel;
    final supabase = _supabaseClientOrNull();
    if (c != null && supabase != null) supabase.removeChannel(c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/nca_icon.png',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'NCA',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public_rounded),
            label: 'Soco',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
        onDestinationSelected: (index) async {
          if (index == 1) {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SocoPage(),
              ),
            );
            return;
          }
          if (index == 2) {
            await _openAppMenu();
          }
        },
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
                      ? (linkCount > 1
                          ? 'WATCH LIVE  •  $linkCount LINES'
                          : 'WATCH LIVE')
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
