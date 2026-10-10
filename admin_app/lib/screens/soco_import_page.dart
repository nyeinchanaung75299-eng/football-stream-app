import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../services/manual_source_url.dart';
import '../services/function_gateway.dart';

class SocoImportPage extends StatefulWidget {
  const SocoImportPage({
    super.key,
    this.initialMatchId,
    this.initialSource = 'soco',
  });

  final String? initialMatchId;
  final String initialSource;

  @override
  State<SocoImportPage> createState() => _SocoImportPageState();
}

class _SocoImportPageState extends State<SocoImportPage> {
  static const _pagesMirrorBase =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources';
  static const _rawMirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/sources';

  static final bool _enableNoVpnFallback =
      const String.fromEnvironment(
        'ENABLE_NO_VPN_FALLBACK',
        defaultValue: '0',
      ).trim() ==
      '1';
  String? targetMatchId;
  bool loading = false;
  bool availableOnly = true;
  String source = 'soco';
  String dayFilter = 'today';
  String? errorText;
  List<Map<String, dynamic>> sourceMatches = const [];
  final Map<String, String> _anchorStatuses = <String, String>{};
  final Map<String, int> _anchorLineCounts = <String, int>{};
  int _anchorStatusEpoch = 0;
  String? _extractingAnchorKey;
  late Future<List<Map<String, dynamic>>> _targetMatchesFuture;
  Timer? _sourceRefreshTimer;
  bool _backgroundRefreshBusy = false;
  int _sourceLoadEpoch = 0;
  int _sourceSelectionEpoch = 0;
  bool _addingLine = false;
  final _playzServerName = TextEditingController(text: 'Server 1');
  final _playzUrl = TextEditingController();
  final _playzReferer = TextEditingController();
  final _playzOrigin = TextEditingController();
  String _playzType = 'auto';

  @override
  void initState() {
    super.initState();
    targetMatchId = widget.initialMatchId;
    _targetMatchesFuture = _loadTargetMatches();
    final requested = widget.initialSource.trim().toLowerCase();
    source = const {'soco', 'yyzb', 'fawa', 'cola', 'playz'}.contains(requested)
        ? requested
        : 'soco';
    dayFilter =
        (source == 'fawa' || source == 'cola' || source == 'playz') ? 'all' : 'today';
    _loadSoco();
    _sourceRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshSourceInBackground()),
    );
  }

  @override
  void dispose() {
    _sourceLoadEpoch += 1;
    _sourceSelectionEpoch += 1;
    _sourceRefreshTimer?.cancel();
    _playzServerName.dispose();
    _playzUrl.dispose();
    _playzReferer.dispose();
    _playzOrigin.dispose();
    super.dispose();
  }

  Future<void> _refreshSourceInBackground() async {
    if (!mounted || source == 'playz' || loading || _backgroundRefreshBusy) return;
    _backgroundRefreshBusy = true;
    try {
      await _loadSoco(silent: true);
    } finally {
      _backgroundRefreshBusy = false;
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<List<Map<String, dynamic>>> _loadTargetMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,home_team,away_team,kickoff_at,sort_order,is_live,is_active,'
          'is_finished,is_featured,publish_state,deleted_at',
        )
        .eq('is_active', true)
        .order('kickoff_at', ascending: true)
        .order('sort_order', ascending: true)
        .order('home_team', ascending: true)
        .timeout(const Duration(seconds: 10));

    final now = DateTime.now();
    const staleKickoffGrace = Duration(hours: 5);

    return List<Map<String, dynamic>>.from(data)
        .where((row) {
          final kickoff = DateTime.tryParse(
            row['kickoff_at']?.toString() ?? '',
          )?.toLocal();
          final stale = row['is_live'] != true &&
              kickoff != null &&
              now.difference(kickoff) > staleKickoffGrace;

          return row['deleted_at'] == null &&
              row['is_active'] == true &&
              row['is_finished'] != true &&
              row['is_featured'] != false &&
              (row['publish_state'] ?? 'published') == 'published' &&
              !stale;
        })
        .toList();
  }

  Future<Map<String, dynamic>> _loadSourceMirror(String provider) async {
    Object? lastError;
    Map<String, dynamic>? emptyFallback;
    for (final base in const [_pagesMirrorBase, _rawMirrorBase]) {
      try {
        final response = await http
            .get(
              Uri.parse(base + '/' + provider + '.json').replace(
                queryParameters: {
                  't': DateTime.now().millisecondsSinceEpoch.toString(),
                },
              ),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Source mirror HTTP ' + response.statusCode.toString(),
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('Source mirror response is invalid.');
        }
        final data = Map<String, dynamic>.from(decoded);
        final rows = data['matches'];
        if (rows is! List) {
          throw const FormatException('Source mirror match list is invalid.');
        }
        if (rows.isNotEmpty) return data;
        emptyFallback ??= data;
      } catch (e) {
        lastError = e;
      }
    }
    if (emptyFallback != null) return emptyFallback;
    throw Exception(lastError ?? 'Source mirror is unavailable.');
  }

  bool _staleSourceMatch(Map<String, dynamic> row) {
    final kickoff = DateTime.tryParse(
      row['match_time']?.toString() ?? '',
    )?.toUtc();
    if (kickoff == null) return false;
    return DateTime.now().toUtc().difference(kickoff) >
        const Duration(hours: 4);
  }

  Future<void> _loadSoco({bool silent = false}) async {
    final provider = source;
    // PlayZ TV has no verified public listing API. This tab only imports
    // direct streams supplied by the admin, never probes a private app API.
    if (provider == 'playz') {
      ++_sourceLoadEpoch;
      if (mounted) {
        setState(() {
          loading = false;
          sourceMatches = const [];
          errorText = null;
        });
      }
      return;
    }
    final epoch = ++_sourceLoadEpoch;
    bool current() =>
        mounted && source == provider && epoch == _sourceLoadEpoch;
    if (!silent) {
      setState(() {
        loading = true;
        errorText = null;
      });
    }

    try {
      dynamic data;
      if (!_enableNoVpnFallback) {
        data = await FunctionGateway.invoke(
          'source-match-list',
          body: {'source': provider},
        );
        final liveRows = data is Map ? data['matches'] : null;
        if (liveRows is! List) {
          throw const FormatException('Live source match list is invalid.');
        }
      } else {
        try {
          data = await FunctionGateway.invoke(
            'source-match-list',
            body: {'source': provider},
          );
          final liveRows = data is Map ? data['matches'] : null;
          if (liveRows is! List) {
            throw const FormatException('Live source match list is invalid.');
          }
        } catch (_) {
          data = await _loadSourceMirror(provider);
        }
      }

      final rows = data is Map ? data['matches'] : null;
      if (rows is! List) {
        throw const FormatException('Source match list is invalid.');
      }

      final parsed = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => !_staleSourceMatch(row))
          .toList();

      parsed.sort((a, b) {
        final at = DateTime.tryParse(a['match_time']?.toString() ?? '')
                ?.toLocal() ??
            DateTime(9999);
        final bt = DateTime.tryParse(b['match_time']?.toString() ?? '')
                ?.toLocal() ??
            DateTime(9999);
        final byTime = at.compareTo(bt);
        if (byTime != 0) return byTime;
        return (a['home_team'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['home_team'] ?? '').toString().toLowerCase(),
            );
      });

      unawaited(AnalyticsService.capture(
        'source match list loaded',
        properties: {
          'source': provider,
          'match_count': parsed.length,
        },
      ));
      if (!current()) return;
      setState(() {
        sourceMatches = parsed;
        _anchorStatuses.clear();
        _anchorLineCounts.clear();
      });
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          _probeVisibleAnchorStatuses,
        ),
      );
    } catch (e) {
      unawaited(AnalyticsService.capture(
        'source match list failed',
        properties: {'source': provider},
      ));
      if (!current()) return;
      if (!silent) {
        final detail = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          sourceMatches = const [];
          errorText =
              'Could not load ${_sourceLabel(provider)} sources. $detail';
        });
      }
    } finally {
      if (!silent && current()) setState(() => loading = false);
    }
  }

  String _anchorKey(
    Map<String, dynamic> match,
    Map<String, dynamic> anchor, {
    String? provider,
  }) {
    final sourceKey = provider ?? source;
    final matchKey =
        (match['schedule_id'] ?? match['source_id'] ?? match['page_url'] ?? '')
            .toString();
    final roomKey =
        (anchor['room_num'] ?? anchor['page_url'] ?? anchor['uid'] ?? '')
            .toString();
    return '$sourceKey|$matchKey|$roomKey';
  }

  bool _isLiveStatus(dynamic value) {
    if (value == true || value == 1) return true;
    final text = value?.toString().trim().toUpperCase() ?? '';
    return text == '1' ||
        text == 'LIVE' ||
        text == 'LIVING' ||
        text == 'ON' ||
        text == 'ONLINE';
  }

  bool _matchLooksLive(Map<String, dynamic> match) {
    if (_staleSourceMatch(match)) return false;
    if (match['is_live'] == true) return true;

    for (final value in [match['match_status'], match['status']]) {
      final status = value?.toString().trim().toUpperCase() ?? '';
      if (const {'LIVE', 'INPLAY', 'IN_PLAY', '1H', '2H', 'HT'}
          .contains(status)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _probeVisibleAnchorStatuses() async {
    if (!mounted || loading) return;

    final provider = source;
    final epoch = ++_anchorStatusEpoch;
    final matches = _visibleSourceMatches;
    final pending = <Map<String, dynamic>>[];

    for (final match in matches) {
      final anchors = List<Map<String, dynamic>>.from(
        match['anchors'] ?? const [],
      );
      for (final anchor in anchors) {
        final key = _anchorKey(match, anchor, provider: provider);
        if (_anchorStatuses.containsKey(key)) continue;

        if (provider == 'cola' || provider == 'fawa') {
          _anchorStatuses[key] =
              _matchLooksLive(match) ? 'live' : 'ready';
          continue;
        }

        _anchorStatuses[key] = 'checking';
        pending.add({
          'match': match,
          'anchor': anchor,
          'key': key,
        });
      }
    }

    if (mounted && source == provider) setState(() {});

    for (var offset = 0; offset < pending.length; offset += 4) {
      if (!mounted || source != provider || epoch != _anchorStatusEpoch) return;

      final batch = pending.skip(offset).take(4).toList();
      await Future.wait(
        batch.map((item) async {
          final match =
              Map<String, dynamic>.from(item['match'] as Map);
          final anchor =
              Map<String, dynamic>.from(item['anchor'] as Map);
          final key = item['key'].toString();

          try {
            final room = anchor['room_num']?.toString().trim() ?? '';
            if (room.isEmpty) {
              _anchorStatuses[key] = 'offline';
              return;
            }

            final data = await FunctionGateway.invoke(
              'soco-links',
              body: {
                'action': 'streams',
                'source': provider,
                'room_num': room,
                'schedule_id': match['schedule_id'],
                'page_url': anchor['page_url'] ?? match['page_url'],
                'status_only': true,
              },
            );

            if (data is! Map) {
              _anchorStatuses[key] = 'unknown';
              return;
            }

            final lineCount =
                (data['line_count'] as num?)?.toInt() ?? 0;
            _anchorLineCounts[key] = lineCount;

            if (_isLiveStatus(data['live_status'])) {
              _anchorStatuses[key] = 'live';
            } else if (data['ready'] == true || lineCount > 0) {
              _anchorStatuses[key] = 'ready';
            } else {
              _anchorStatuses[key] = 'offline';
            }
          } catch (_) {
            _anchorStatuses[key] = 'unknown';
          }
        }),
      );

      if (mounted && source == provider && epoch == _anchorStatusEpoch) {
        setState(() {});
      }
    }
  }

  int _anchorStatusRank(String? status) {
    return switch (status) {
      'live' => 0,
      'ready' => 1,
      'checking' => 2,
      'unknown' => 3,
      'offline' => 4,
      _ => 3,
    };
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _visibleSourceMatches {
    Iterable<Map<String, dynamic>> rows = sourceMatches;

    if (availableOnly) {
      rows = rows.where((row) {
        final anchors = row['anchors'];
        return anchors is List && anchors.isNotEmpty;
      });
    }

    if (source == 'fawa' || source == 'cola' || dayFilter == 'all') {
      return rows.toList();
    }

    final now = DateTime.now();
    final wanted = dayFilter == 'tomorrow'
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    return rows.where((row) {
      final time = DateTime.tryParse(
        row['match_time']?.toString() ?? '',
      )?.toLocal();
      return time != null && _sameDate(time, wanted);
    }).toList();
  }

  Future<String?> _chooseDestination() async {
    final loaded = await _loadTargetMatches();
    if (!mounted || loaded.isEmpty) return null;

    final targets = List<Map<String, dynamic>>.from(loaded);
    final suggestedId = targetMatchId;
    if (suggestedId != null) {
      targets.sort((a, b) {
        final aSuggested = a['id']?.toString() == suggestedId;
        final bSuggested = b['id']?.toString() == suggestedId;
        if (aSuggested == bSuggested) return 0;
        return aSuggested ? -1 : 1;
      });
    }

    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .9,
        minChildSize: .45,
        builder: (context, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose NCA match',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                itemCount: targets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final m = targets[index];
                  final kickoff = DateTime.tryParse(
                    m['kickoff_at']?.toString() ?? '',
                  )?.toLocal();
                  final when = kickoff == null
                      ? '--:--'
                      : DateFormat('dd MMM • h:mm a', 'en_US').format(kickoff);

                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    leading: const Icon(Icons.sports_soccer_rounded),
                    title: Text(
                      '${m['home_team']} vs ${m['away_team']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(when),
                    trailing: m['id']?.toString() == suggestedId
                        ? const Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      m['id']?.toString(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAnchor(
    Map<String, dynamic> match,
    Map<String, dynamic> anchor,
  ) async {
    final room = anchor['room_num']?.toString().trim() ?? '';
    if (room.isEmpty) return;

    final extractingKey = _anchorKey(match, anchor);
    final provider = source;
    final epoch = _sourceSelectionEpoch;
    bool current() =>
        mounted && source == provider && epoch == _sourceSelectionEpoch;
    if (_extractingAnchorKey != null) return;
    setState(() => _extractingAnchorKey = extractingKey);

    try {
      final data = await FunctionGateway.invoke(
        'soco-links',
        body: {
          'action': 'streams',
          'source': provider,
          'room_num': room,
          'schedule_id': match['schedule_id'],
          'page_url': anchor['page_url'] ?? match['page_url'],
          'skip_probe': true,
        },
      );

      final rows = data is Map ? data['lines'] : null;
      if (!current()) return;
      if (rows is! List) {
        throw const FormatException('No stream quality list returned.');
      }

      final lines = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => (row['url'] ?? '').toString().trim().isNotEmpty)
          .toList();

      final statusKey = _anchorKey(match, anchor, provider: provider);
      final sourceIsLive =
          data is Map && _isLiveStatus(data['live_status']);
      final hasHealthy = lines.any((line) {
        final health =
            (line['health_status'] ?? '').toString().toLowerCase();
        return health == 'healthy' || health == 'slow';
      });
      if (mounted) {
        setState(() {
          _anchorLineCounts[statusKey] = lines.length;
          _anchorStatuses[statusKey] = sourceIsLive
              ? 'live'
              : (hasHealthy || lines.isNotEmpty ? 'ready' : 'offline');
        });
      }

      unawaited(AnalyticsService.capture(
        'source lines loaded',
        properties: {
          'source': provider,
          'line_count': lines.length,
          'source_live':
              data is Map &&
              (data['live_status'] == true ||
                  data['live_status'] == 1 ||
                  data['live_status']?.toString() == '1'),
        },
      ));

      if (!current()) return;
      if (lines.isEmpty) {
        message('No playable line is available for this streamer.');
        return;
      }

      await _showQualityPicker(
        match: match,
        anchor: anchor,
        lines: lines,
        sourceLiveStatus: data is Map ? data['live_status'] : null,
      );
    } catch (e) {
      unawaited(AnalyticsService.capture(
        'source lines failed',
        properties: {'source': source},
      ));
      if (!current()) return;
      final detail = e.toString().replaceFirst('Exception: ', '');
      message(
        'Could not load ${_sourceLabel(provider)} stream links. $detail',
      );
    } finally {
      if (mounted && _extractingAnchorKey == extractingKey) {
        setState(() => _extractingAnchorKey = null);
      }
    }
  }

  Future<void> _showQualityPicker({
    required Map<String, dynamic> match,
    required Map<String, dynamic> anchor,
    required List<Map<String, dynamic>> lines,
    dynamic sourceLiveStatus,
  }) async {
    final anchorName =
        (anchor['nick_name'] ?? 'Streamer').toString().trim();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Stream Quality',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${match['home_team']} vs ${match['away_team']} • $anchorName',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (sourceLiveStatus != null) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final live = sourceLiveStatus == true ||
                        sourceLiveStatus == 1 ||
                        sourceLiveStatus.toString() == '1';
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (live ? Colors.green : Colors.orange)
                              .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          live ? 'SOURCE LIVE' : 'SOURCE NOT LIVE',
                          style: TextStyle(
                            color: live ? Colors.green : Colors.orange,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              ...lines.map((line) {
                final label = (line['label'] ?? 'Stream').toString();
                final type =
                    (line['stream_type'] ?? 'auto').toString().toUpperCase();
                final url = (line['url'] ?? '').toString();
                final referer = (line['referer'] ?? '').toString().trim();
                final origin = (line['origin'] ?? '').toString().trim();
                final health =
                    (line['health_status'] ?? '').toString().toLowerCase();

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          type == 'HLS'
                              ? Icons.play_circle_fill_rounded
                              : Icons.video_file_rounded,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (health.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (health == 'healthy'
                                                ? Colors.green
                                                : health == 'failed' ||
                                                        health == 'dead'
                                                    ? Colors.red
                                                    : Colors.orange)
                                            .withValues(alpha: .12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        health.toUpperCase(),
                                        style: TextStyle(
                                          color: health == 'healthy'
                                              ? Colors.green
                                              : health == 'failed' ||
                                                      health == 'dead'
                                                  ? Colors.red
                                                  : Colors.orange,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (referer.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Referer: $referer',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (origin.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Origin: $origin',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy link',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: url),
                            );
                            unawaited(AnalyticsService.capture(
                              'source link copied',
                              properties: {
                                'source': source,
                                'stream_type':
                                    (line['stream_type'] ?? 'auto').toString(),
                              },
                            ));
                            message('${_sourceLabel(source)} link copied.');
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final added = await _addLine(
                              line: line,
                              anchorName: anchorName,
                            );
                            if (added && sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          child: const Text('ADD'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  targetMatchId == null
                      ? 'Each ADD will ask which NCA match to use.'
                      : 'Each ADD will still ask for the NCA match. The selected destination is shown first.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _addLine({
    required Map<String, dynamic> line,
    required String anchorName,
  }) async {
    if (_addingLine) return false;
    _addingLine = true;
    final provider = source;
    try {
      // Always require an explicit destination confirmation. The dropdown and
    // initial match only suggest which match should appear first.
    final presetTarget = targetMatchId;
    final target = await _chooseDestination();
    if (target == null) return false;

    final url = (line['url'] ?? '').toString().trim();
    if (url.isEmpty) return false;

    final sourceName = _sourceLabel(provider);
    final label = (line['label'] ?? sourceName).toString();
    final type = (line['stream_type'] ?? 'auto').toString();
    final resolution = (line['resolution'] ?? label).toString();
    final fullLabel = '$sourceName • $anchorName • $label';

    final exact = await Supabase.instance.client
        .from('stream_links')
        .select('id,is_active,expires_at')
        .eq('match_id', target)
        .eq('stream_url', url)
        .maybeSingle()
          .timeout(const Duration(seconds: 10));

    Map<String, dynamic> saved;
    if (exact != null) {
      // A previously imported short-lived line may have been disabled after
      // its signed URL expired. Re-enable it when the source returns the same
      // URL again instead of treating it as an unusable duplicate.
      saved = await Supabase.instance.client
          .from('stream_links')
          .update({
            'label': fullLabel,
            'resolution': resolution,
            'stream_type': type,
            'referer': nullable(line['referer']?.toString()),
            'origin': nullable(line['origin']?.toString()),
            'is_active': true,
            'expires_at': line['expires_at'],
            'health_status': 'unknown',
            'health_latency_ms': null,
            'last_checked_at': null,
          })
          .eq('id', exact['id'])
          .select('id')
          .single()
            .timeout(const Duration(seconds: 12));
    } else {
      // Soco/YYZB/Cola signed URLs rotate. Match the logical line by its
      // stable label/type/resolution and replace the expired URL in-place so
      // the viewer gets the fresh token without accumulating dead rows.
      final sameLogical = await Supabase.instance.client
          .from('stream_links')
          .select('id')
          .eq('match_id', target)
          .eq('label', fullLabel)
          .eq('stream_type', type)
          .eq('resolution', resolution)
          .maybeSingle()
            .timeout(const Duration(seconds: 10));

      if (sameLogical != null) {
        saved = await Supabase.instance.client
            .from('stream_links')
            .update({
              'stream_url': url,
              'referer': nullable(line['referer']?.toString()),
              'origin': nullable(line['origin']?.toString()),
              'is_active': true,
              'expires_at': line['expires_at'],
              'health_status': 'unknown',
              'health_latency_ms': null,
              'last_checked_at': null,
            })
            .eq('id', sameLogical['id'])
            .select('id')
            .single()
              .timeout(const Duration(seconds: 12));
      } else {
        saved = await Supabase.instance.client
            .from('stream_links')
            .insert({
              'match_id': target,
              'label': fullLabel,
              'resolution': resolution,
              'stream_type': type,
              'stream_url': url,
              'referer': nullable(line['referer']?.toString()),
              'origin': nullable(line['origin']?.toString()),
              'use_webview': false,
              'webview_url': null,
              'send_notification': false,
              'is_active': true,
              'expires_at': line['expires_at'],
            })
            .select('id')
            .single()
              .timeout(const Duration(seconds: 12));
      }
    }

      // Saving is complete. A slow health check must not keep ADD waiting or
      // invite a duplicate submission. Its result is keyed to the saved row,
      // never to whichever provider/destination the UI later selects.
      unawaited(_checkSavedLine(saved['id'].toString(), provider));
      unawaited(AnalyticsService.capture(
      'source line imported',
      properties: {
        'source': provider,
        'stream_type': type,
        'resolution': resolution,
        'destination_preset': presetTarget != null,
        'health_status': 'pending',
      },
    ));

    message('$sourceName $label added. Health check is pending.');
    return true;
    } on TimeoutException {
      message('Could not confirm the save. Refresh before trying again.');
      return false;
    } catch (_) {
      message('Could not add the server. Please retry.');
      return false;
    } finally {
      _addingLine = false;
    }
  }

  Future<void> _checkSavedLine(String id, String provider) async {
    try {
      final checked =
          await FunctionGateway.invoke('stream-health', body: {'link_id': id})
              .timeout(const Duration(seconds: 12));
      unawaited(AnalyticsService.capture('stream health checked', properties: {
        'scope': 'link',
        'source': provider,
        if (checked is Map && checked['health_status'] != null)
          'health_status': checked['health_status'].toString(),
      }));
    } catch (_) {
      // System Health and Stream Servers show the eventual persisted result.
      // Do not show an error on a newer source/destination screen.
    }
  }

  String? nullable(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Future<void> _addPlayzManualLine() async {
    final url = _playzUrl.text.trim();
    final inferred = detectManualStreamType(url);
    final type = _playzType == 'auto' ? inferred : _playzType;
    if (type == null || !isValidManualStreamUrl(url, streamType: type)) {
      message(
        'Enter an authorized direct HTTP(S) media URL (M3U8, MPD, '
        'FLV or MP4). For extensionless URLs, select the stream type.',
      );
      return;
    }

    final name = _playzServerName.text.trim().isEmpty
        ? 'Server 1'
        : _playzServerName.text.trim();
    final added = await _addLine(
      anchorName: 'Manual',
      line: {
        'label': name,
        'url': url,
        'stream_type': type,
        'resolution': type.toUpperCase(),
        'referer': _playzReferer.text.trim(),
        'origin': _playzOrigin.text.trim(),
      },
    );
    if (added && mounted) {
      _playzUrl.clear();
    }
  }

  Widget _playzManualCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PlayZ TV · Manual stream',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'A public PlayZ TV football listing/API has not been verified. '
              'Paste only a direct stream URL you are authorized to use. '
              'This does not extract links from the APK or bypass app/DRM access.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _playzServerName,
              decoration: const InputDecoration(
                labelText: 'Server name',
                hintText: 'Server 1',
                prefixIcon: Icon(Icons.dns_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playzUrl,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Direct stream URL',
                hintText: 'https://example.com/live/stream.m3u8',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              onChanged: (value) {
                final inferred = detectManualStreamType(value);
                if (inferred != null && inferred != _playzType) {
                  setState(() => _playzType = inferred);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _playzType,
              decoration: const InputDecoration(labelText: 'Stream type'),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto / detect')),
                DropdownMenuItem(value: 'hls', child: Text('HLS / M3U8')),
                DropdownMenuItem(value: 'dash', child: Text('DASH / MPD')),
                DropdownMenuItem(value: 'flv', child: Text('FLV')),
                DropdownMenuItem(value: 'mp4', child: Text('MP4')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _playzType = value);
              },
            ),
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Optional stream headers'),
              children: [
                TextField(
                  controller: _playzReferer,
                  decoration: const InputDecoration(
                    labelText: 'Referer (if authorized)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _playzOrigin,
                  decoration: const InputDecoration(
                    labelText: 'Origin (if authorized)',
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _addingLine ? null : _addPlayzManualLine,
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('ADD TO NCA MATCH'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You must confirm the destination match before saving. '
              'A reachability check follows; successful playback is not guaranteed.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String value) {
    switch (value) {
      case 'playz':
        return 'PlayZ TV';
      case 'yyzb':
        return 'YYZB';
      case 'fawa':
        return 'Fawa';
      case 'cola':
        return 'ColaTV';
      default:
        return 'Soco';
    }
  }

  Widget _sourceButton(String value, String label) {
    final selected = source == value;
    final onPressed = loading
        ? null
        : () {
            setState(() {
              _sourceSelectionEpoch += 1;
              source = value;
              dayFilter =
                  (value == 'fawa' || value == 'cola' || value == 'playz') ? 'all' : 'today';
              sourceMatches = const [];
              errorText = null;
              _anchorStatusEpoch += 1;
              _anchorStatuses.clear();
              _anchorLineCounts.clear();
            });
            AnalyticsService.capture(
              'source provider selected',
              properties: {'source': value},
            );
            _loadSoco();
          };

    return selected
        ? FilledButton.tonal(
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            child: Text(label),
          );
  }

  Widget _dayButton(String value, String label) {
    final selected = dayFilter == value;

    void selectDay() {
      setState(() => dayFilter = value);
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          _probeVisibleAnchorStatuses,
        ),
      );
    }

    return selected
        ? FilledButton.tonal(
            onPressed: selectDay,
            child: Text(label),
          )
        : TextButton(
            onPressed: selectDay,
            child: Text(label),
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _visibleSourceMatches;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Source Picker'),
        actions: [
          IconButton(
            tooltip: 'Refresh source',
            onPressed: loading || source == 'playz' ? null : _loadSoco,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _targetMatchesFuture,
        builder: (context, targetSnapshot) {
          final targets =
              targetSnapshot.data ?? const <Map<String, dynamic>>[];

          if (targetSnapshot.connectionState == ConnectionState.done &&
              targetSnapshot.hasData &&
              targetMatchId != null &&
              !targets.any((row) => row['id'] == targetMatchId)) {
            // Only invalidate a preset destination after a completed query.
            // A FutureBuilder waiting snapshot must not erase it.
            targetMatchId = null;
          }

          return RefreshIndicator(
            onRefresh: _loadSoco,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: DropdownButtonFormField<String>(
                      value: targetMatchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Suggested destination (ADD confirms)',
                        prefixIcon: Icon(Icons.sports_soccer_rounded),
                      ),
                      items: targets.map((m) {
                        final kickoff = DateTime.tryParse(
                          m['kickoff_at']?.toString() ?? '',
                        )?.toLocal();
                        final when = kickoff == null
                            ? '--:--'
                            : DateFormat('dd MMM • h:mm a', 'en_US').format(kickoff);
                        return DropdownMenuItem(
                          value: m['id'] as String,
                          child: Text(
                            '$when · ${m['home_team']} vs ${m['away_team']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => targetMatchId = value),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sourceButton('soco', 'Soco'),
                    _sourceButton('yyzb', 'YYZB'),
                    _sourceButton('fawa', 'Fawa'),
                    _sourceButton('cola', 'ColaTV'),
                    _sourceButton('playz', 'PlayZ TV'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Source: ${_sourceLabel(source)}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (source == 'playz') _playzManualCard(colors),
                if (source != 'playz') SwitchListTile.adaptive(
                  value: availableOnly,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Available only',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Hide matches that have no source yet.',
                  ),
                  onChanged: (value) =>
                      setState(() => availableOnly = value),
                ),
                const SizedBox(height: 4),
                if (source != 'playz' && source != 'fawa' && source != 'cola')
                  Row(
                    children: [
                      _dayButton('today', 'Today'),
                    const SizedBox(width: 4),
                    _dayButton('tomorrow', 'Tomorrow'),
                    const SizedBox(width: 4),
                    _dayButton('all', 'All'),
                    const Spacer(),
                      if (loading)
                        const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  )
                else if (loading)
                  const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                const SizedBox(height: 8),
                if (errorText != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        errorText!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ),
                if (source != 'playz' && !loading && visible.isEmpty && errorText == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No football matches in this source section.'),
                    ),
                  ),
                ...visible.map((match) {
                  final kickoff = DateTime.tryParse(
                    match['match_time']?.toString() ?? '',
                  )?.toLocal();
                  final anchors = List<Map<String, dynamic>>.from(
                    match['anchors'] ?? const [],
                  )..sort((a, b) {
                      final aStatus = _anchorStatuses[
                          _anchorKey(match, a)
                      ];
                      final bStatus = _anchorStatuses[
                          _anchorKey(match, b)
                      ];
                      return _anchorStatusRank(aStatus)
                          .compareTo(_anchorStatusRank(bStatus));
                    });

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (match['league'] ?? 'Football').toString(),
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (match['hot'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'HOT',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${match['home_team']} vs ${match['away_team']}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            kickoff == null
                                ? 'Unknown time'
                                : DateFormat('dd MMM • h:mm a', 'en_US').format(kickoff),
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (anchors.isEmpty)
                            Text(
                              'No streamer is listed yet.',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: anchors.map((anchor) {
                                final name =
                                    (anchor['nick_name'] ?? 'Streamer')
                                        .toString();
                                final key = _anchorKey(match, anchor);
                                final status =
                                    _anchorStatuses[key] ?? 'unknown';
                                final lineCount =
                                    _anchorLineCounts[key] ?? 0;

                                final icon = switch (status) {
                                  'live' => Icons.sensors_rounded,
                                  'ready' => Icons.check_circle_rounded,
                                  'offline' => Icons.cloud_off_rounded,
                                  'checking' => Icons.sync_rounded,
                                  _ => Icons.help_outline_rounded,
                                };
                                final suffix = switch (status) {
                                  'live' => ' • LIVE',
                                  'ready' => lineCount > 0
                                      ? ' • READY ($lineCount)'
                                      : ' • READY',
                                  'offline' => ' • OFFLINE',
                                  'checking' => ' • CHECKING',
                                  _ => ' • UNKNOWN',
                                };
                                final color = switch (status) {
                                  'live' => Colors.redAccent,
                                  'ready' => Colors.green,
                                  'offline' => Colors.blueGrey,
                                  'checking' => Colors.orange,
                                  _ => colors.onSurfaceVariant,
                                };

                                final extracting =
                                    _extractingAnchorKey == key;

                                return OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: color,
                                    side: BorderSide(
                                      color: color.withValues(alpha: .55),
                                    ),
                                  ),
                                  onPressed: status == 'checking' ||
                                          _extractingAnchorKey != null
                                      ? null
                                      : () => _openAnchor(match, anchor),
                                  icon: extracting
                                      ? SizedBox(
                                          width: 17,
                                          height: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: color,
                                          ),
                                        )
                                      : Icon(icon, size: 17),
                                  label: Text(
                                    extracting
                                        ? '$name • LOADING'
                                        : '$name$suffix',
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
