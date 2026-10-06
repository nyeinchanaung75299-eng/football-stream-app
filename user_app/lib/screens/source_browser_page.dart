import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native_player.dart';

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
  static const _fallback = 'https://football-api.nyeinchanaung.ccwu.cc';
  static const _backup =
      'https://football-public-api.nyeinchanaung75299-eng.workers.dev';
  static const _supabaseFunction =
      'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/soco-links';
  static const _sourceMirrorBase =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources';
  static const _rawSourceMirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/sources';

  late Future<List<Map<String, dynamic>>> _future;

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
  List<String> get bases => <String>{
        _primary.trim().replaceAll(RegExp(r'/+$'), ''),
        _fallback,
        _backup,
      }.where((x) => x.isNotEmpty).toList();

  @override
  void initState() {
    super.initState();
    _future = _loadMatches();
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

  bool _live(Map<String, dynamic> m) {
    if (m['hot'] == true) return true;
    final status =
        (m['status'] ?? m['match_status'] ?? '').toString().toUpperCase();
    return status == 'LIVE' || status == 'INPLAY' || status == 'IN_PLAY';
  }

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
    final rows =
        raw.map((x) => Map<String, dynamic>.from(x as Map)).toList();
    rows.sort((a, b) {
      if (_live(a) != _live(b)) return _live(a) ? -1 : 1;
      final at = DateTime.tryParse(a['match_time']?.toString() ?? '');
      final bt = DateTime.tryParse(b['match_time']?.toString() ?? '');
      if (at == null && bt == null) return _matchName(a).compareTo(_matchName(b));
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
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
    final rows =
        raw.map((x) => Map<String, dynamic>.from(x as Map)).toList();
    rows.sort((a, b) {
      if (_live(a) != _live(b)) return _live(a) ? -1 : 1;
      final at = DateTime.tryParse(a['match_time']?.toString() ?? '');
      final bt = DateTime.tryParse(b['match_time']?.toString() ?? '');
      if (at == null && bt == null) {
        return _matchName(a).compareTo(_matchName(b));
      }
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
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
    final rows =
        raw.map((x) => Map<String, dynamic>.from(x as Map)).toList();
    rows.sort((a, b) {
      if (_live(a) != _live(b)) return _live(a) ? -1 : 1;
      final at = DateTime.tryParse(a['match_time']?.toString() ?? '');
      final bt = DateTime.tryParse(b['match_time']?.toString() ?? '');
      if (at == null && bt == null) return _matchName(a).compareTo(_matchName(b));
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
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
    try {
      final workerJobs =
          bases.map<Future<List<Map<String, dynamic>>> Function()>(
            (base) => () => _loadFrom(base),
          ).toList();
      final rows = await _hedged(
        [
          if (workerJobs.isNotEmpty) workerJobs.first,
          () => _loadFromMirror(),
          () => _loadFromMirror(_rawSourceMirrorBase),
          () => _loadFromSupabase(),
          ...workerJobs.skip(1),
        ],
      );
      unawaited(_saveLastGood(rows));
      return rows;
    } catch (error, stack) {
      final cached = await _loadLastGood();
      if (cached != null && cached.isNotEmpty) return cached;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _refresh() async {
    final next = _loadMatches();
    setState(() => _future = next);
    await next;
  }

  List<Map<String, dynamic>> _anchors(Map<String, dynamic> m) {
    final raw = m['anchors'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
    }
    final room =
        (m['source_id'] ?? m['schedule_id'] ?? '').toString().trim();
    final page = m['page_url']?.toString().trim() ?? '';
    if (room.isEmpty && page.isEmpty) return const [];
    return [
      {'room_num': room, 'page_url': page}
    ];
  }

  Future<List<Map<String, dynamic>>> _anchorFrom(
    String base,
    Map<String, dynamic> m,
    Map<String, dynamic> anchor,
  ) async {
    final response = await http
        .post(
          Uri.parse(base + '/sources/' + source + '/streams'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
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
    Map<String, dynamic> anchor,
  ) async {
    final response = await http
        .get(
          Uri.parse(_supabaseFunction).replace(
            queryParameters: {
              'viewer_public': '1',
              'action': 'streams',
              'source': source,
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
        'id': source +
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
  ) =>
      _hedged(
        [
          if (bases.isNotEmpty) () => _anchorFrom(bases.first, m, anchor),
          () => _anchorFromSupabase(m, anchor),
          ...bases.skip(1).map<Future<List<Map<String, dynamic>>> Function()>(
            (base) => () => _anchorFrom(base, m, anchor),
          ),
        ],
      );

  Future<List<Map<String, dynamic>>> _streams(
    Map<String, dynamic> m,
  ) async {
    final groups = await Future.wait(
      _anchors(m).map((a) async {
        try {
          return await _anchor(m, a);
        } catch (_) {
          return const <Map<String, dynamic>>[];
        }
      }),
      eagerError: false,
    );
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final group in groups) {
      for (final row in group) {
        final id = row['id']?.toString() ?? '';
        final url = row['stream_url']?.toString() ?? '';
        final key = id.isNotEmpty ? 'id:' + id : 'url:' + url;
        if (url.trim().isNotEmpty && seen.add(key)) out.add(row);
      }
    }
    int rank(Map<String, dynamic> x) {
      final t = (x['stream_type'] ?? 'auto').toString().toLowerCase();
      if (t == 'hls' || t == 'm3u8') return 0;
      if (t == 'dash' || t == 'mpd') return 1;
      if (t == 'mp4') return 2;
      if (t == 'auto') return 3;
      if (t == 'flv') return 4;
      return 5;
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

    out.sort((a, b) {
      final health = healthRank(a).compareTo(healthRank(b));
      if (health != 0) return health;
      final format = rank(a).compareTo(rank(b));
      if (format != 0) return format;
      final ap = (a['priority'] as num?)?.toInt() ?? 100;
      final bp = (b['priority'] as num?)?.toInt() ?? 100;
      return ap.compareTo(bp);
    });
    return out;
  }

  Future<void> _watch(Map<String, dynamic> m) async {
    if (_anchors(m).isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> rows = const [];
    try {
      rows = await _streams(m);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ' + title + ' stream is available now.')),
      );
      return;
    }

    final sources = rows
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
            })
        .toList();

    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
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
                    sources.length.toString() + ' lines',
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
                  final quality = x['resolution']?.toString().trim() ?? '';
                  final health =
                      x['healthStatus']?.toString().toLowerCase() ?? 'unknown';
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
                      label.isEmpty ? 'Line ' + (i + 1).toString() : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [quality, type, healthLabel]
                          .where((x) => x.isNotEmpty)
                          .join(' • '),
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
      ),
    );

    if (picked == null || !mounted) return;
    await NativePlayer.open(
      context: context,
      sources: sources,
      selectedIndex: picked,
      title: _matchName(m),
      matchId: source + ':' +
          (m['source_id'] ?? m['schedule_id'] ?? '').toString(),
    );
  }

  void _select(int index) {
    if (index == navIndex) return;
    if (index == 0) {
      Navigator.of(context).popUntil((route) => route.isFirst);
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title + ' Live',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError && !snap.hasData) {
            return _StateView(
              text: 'Could not load ' + title,
              onRefresh: _refresh,
            );
          }
          final matches = snap.data ?? const <Map<String, dynamic>>[];
          if (matches.isEmpty) {
            return _StateView(
              text: 'No ' + title + ' matches now',
              onRefresh: _refresh,
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final m = matches[i];
                final live = _live(m);
                final ready = _anchors(m).isNotEmpty;
                final time = DateTime.tryParse(
                  m['match_time']?.toString() ?? '',
                )?.toLocal();

                return Card(
                  margin: EdgeInsets.zero,
                  elevation: live ? 2 : 0,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: live
                          ? Colors.redAccent.withValues(alpha: .35)
                          : colors.outlineVariant.withValues(alpha: .45),
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
                                (m['league'] ?? 'Football').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (live)
                              const _Pill(
                                text: 'LIVE',
                                color: Colors.redAccent,
                              )
                            else if (time != null)
                              _Pill(
                                text: DateFormat('HH:mm').format(time),
                                color: colors.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Team(
                                name: (m['home_team'] ?? 'Home').toString(),
                                logo: (m['home_logo'] ?? m['home_logo_url'])
                                    ?.toString(),
                              ),
                            ),
                            SizedBox(
                              width: 72,
                              child: Column(
                                children: [
                                  const Text(
                                    'VS',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (time != null)
                                    Text(
                                      DateFormat('dd MMM').format(time),
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _Team(
                                name: (m['away_team'] ?? 'Away').toString(),
                                logo: (m['away_logo'] ?? m['away_logo_url'])
                                    ?.toString(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: FilledButton.icon(
                            onPressed: ready ? () => _watch(m) : null,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: Text(
                              ready ? 'WATCH LIVE • AUTO LINES' : 'NOT READY',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_soccer_outlined),
            selectedIcon: Icon(Icons.sports_soccer_rounded),
            label: 'Soco',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors_rounded),
            label: 'YYZB',
          ),
          NavigationDestination(
            icon: Icon(Icons.language_outlined),
            selectedIcon: Icon(Icons.language_rounded),
            label: 'Fawa',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv_rounded),
            label: 'ColaTV',
          ),
        ],
        onDestinationSelected: _select,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _StateView extends StatelessWidget {
  const _StateView({required this.text, required this.onRefresh});
  final String text;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_soccer_outlined, size: 54),
            const SizedBox(height: 12),
            Text(
              text,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => onRefresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REFRESH'),
            ),
          ],
        ),
      );
}
