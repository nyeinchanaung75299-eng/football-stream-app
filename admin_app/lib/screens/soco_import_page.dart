import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../football_english.dart';
import '../services/manual_source_url.dart';
import '../services/function_gateway.dart';
import '../services/stream_library_service.dart';
import '../source_line_validation.dart';

@visibleForTesting
List<Map<String, dynamic>> validateSourceMatchRows(
  dynamic payload,
  String provider,
) {
  if (payload is! Map) {
    throw const FormatException('Source match response is invalid.');
  }

  final expected = provider.trim().toLowerCase();
  final responseSource = payload['source']?.toString().trim().toLowerCase();
  if (expected.isEmpty || responseSource != expected) {
    throw FormatException('Source response mismatch: expected $expected.');
  }

  final rows = payload['matches'];
  if (rows is! List) {
    throw const FormatException('Source match list is invalid.');
  }

  return rows.map<Map<String, dynamic>>((row) {
    if (row is! Map) {
      throw const FormatException('Source match row is invalid.');
    }
    final parsed = Map<String, dynamic>.from(row);
    final rowSource = parsed['source']?.toString().trim().toLowerCase();
    if (rowSource != expected) {
      throw FormatException(
        'Source response mismatch: expected $expected.',
      );
    }
    return parsed;
  }).toList(growable: false);
}

class SocoImportPage extends StatefulWidget {
  const SocoImportPage({
    super.key,
    this.initialMatchId,
    this.initialSource = 'soco',
    this.initialReferer,
  });

  final String? initialMatchId;
  final String initialSource;
  final String? initialReferer;

  @override
  State<SocoImportPage> createState() => _SocoImportPageState();
}

class _SocoImportPageState extends State<SocoImportPage> {
  bool get _isManualSource => source == 'playz';

  static const _pagesMirrorBase =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources';
  static const _rawMirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/sources';

  static final bool _enableNoVpnFallback = const String.fromEnvironment(
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
  // Status is advisory, not a prerequisite for tapping a stream source.
  final Map<String, DateTime> _anchorStatusCheckedAt = <String, DateTime>{};
  static const _statusTtl = Duration(minutes: 2);
  // Check the first on-screen matches; leave the rest tappable as UNKNOWN
  // instead of firing dozens of stream resolver requests on every open.
  static const _initialStatusProbeLimit = 8;
  int _anchorStatusEpoch = 0;
  String? _extractingAnchorKey;
  Timer? _sourceRefreshTimer;
  bool _backgroundRefreshBusy = false;
  int _sourceLoadEpoch = 0;
  bool _addingLine = false;
  bool _savingLibrary = false;
  String? _deletingLibraryId;
  late final StreamLibraryService _streamLibrary;
  Future<List<StreamLibraryEntry>>? _libraryFuture;
  final _playzServerName = TextEditingController(text: 'Server 1');
  final _playzUrl = TextEditingController();
  final _playzReferer = TextEditingController();
  final _playzOrigin = TextEditingController();
  final _playzKeyId = TextEditingController();
  final _playzKeyData = TextEditingController();
  String _playzType = 'auto';

  @override
  void initState() {
    super.initState();
    _streamLibrary = StreamLibraryService(Supabase.instance.client);
    targetMatchId = widget.initialMatchId;
    if (widget.initialReferer != null) {
      _playzReferer.text = widget.initialReferer!;
      final page = Uri.tryParse(widget.initialReferer!);
      if (page != null) _playzOrigin.text = page.origin;
    }
    final requested = widget.initialSource.trim().toLowerCase();
    source = const {
      'soco',
      'yyzb',
      'fawa',
      'cola',
      'playz',
    }.contains(requested)
        ? requested
        : 'soco';
    if (_isManualSource) _libraryFuture = _streamLibrary.list();
    dayFilter = (source == 'fawa' || source == 'cola' || _isManualSource)
        ? 'all'
        : 'today';
    _loadSoco();
    _sourceRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshSourceInBackground()),
    );
  }

  @override
  void dispose() {
    _sourceLoadEpoch += 1;
    _sourceRefreshTimer?.cancel();
    _playzServerName.dispose();
    _playzUrl.dispose();
    _playzReferer.dispose();
    _playzOrigin.dispose();
    _playzKeyId.dispose();
    _playzKeyData.dispose();
    super.dispose();
  }

  Future<void> _refreshSourceInBackground() async {
    if (!mounted || _isManualSource || loading || _backgroundRefreshBusy)
      return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (_extractingAnchorKey != null ||
        (state != null && state != AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent == false) return;
    _backgroundRefreshBusy = true;
    try {
      await _loadSoco(silent: true);
    } finally {
      _backgroundRefreshBusy = false;
    }
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

    return List<Map<String, dynamic>>.from(data).where((row) {
      final kickoff =
          DateTime.tryParse(row['kickoff_at']?.toString() ?? '')?.toLocal();
      final stale = row['is_live'] != true &&
          kickoff != null &&
          now.difference(kickoff) > staleKickoffGrace;

      return row['deleted_at'] == null &&
          row['is_active'] == true &&
          row['is_finished'] != true &&
          row['is_featured'] != false &&
          (row['publish_state'] ?? 'published') == 'published' &&
          !stale;
    }).toList();
  }

  Future<Map<String, dynamic>> _loadSourceMirror(String provider) async {
    Object? lastError;
    Map<String, dynamic>? emptyFallback;
    for (final base in const [_pagesMirrorBase, _rawMirrorBase]) {
      try {
        final response = await http.get(
          Uri.parse(base + '/' + provider + '.json').replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          ),
          headers: const {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 18));
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
    final kickoff =
        DateTime.tryParse(row['match_time']?.toString() ?? '')?.toUtc();
    if (kickoff == null) return false;
    return DateTime.now().toUtc().difference(kickoff) >
        const Duration(hours: 4);
  }

  Future<void> _loadSoco({bool silent = false}) async {
    final provider = source;
    // PlayZ currently supports direct-media manual import only.
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
        validateSourceMatchRows(data, provider);
      } else {
        try {
          data = await FunctionGateway.invoke(
            'source-match-list',
            body: {'source': provider},
          );
          validateSourceMatchRows(data, provider);
        } catch (_) {
          data = await _loadSourceMirror(provider);
          validateSourceMatchRows(data, provider);
        }
      }

      final rows = validateSourceMatchRows(data, provider);

      final parsed = rows
          .map((row) => englishSourceMatch(row, provider))
          .where((row) => !_staleSourceMatch(row))
          .toList();

      parsed.sort((a, b) {
        final at =
            DateTime.tryParse(a['match_time']?.toString() ?? '')?.toLocal() ??
                DateTime(9999);
        final bt =
            DateTime.tryParse(b['match_time']?.toString() ?? '')?.toLocal() ??
                DateTime(9999);
        final byTime = at.compareTo(bt);
        if (byTime != 0) return byTime;
        return (a['home_team'] ?? '').toString().toLowerCase().compareTo(
              (b['home_team'] ?? '').toString().toLowerCase(),
            );
      });

      unawaited(
        AnalyticsService.capture(
          'source match list loaded',
          properties: {'source': provider, 'match_count': parsed.length},
        ),
      );
      if (!current()) return;
      // A one-minute background catalog refresh must not reset all streamer
      // statuses and trigger an identical network probe storm.
      if (silent && jsonEncode(sourceMatches) == jsonEncode(parsed)) return;
      final currentKeys = <String>{
        for (final match in parsed)
          for (final anchor in List<Map<String, dynamic>>.from(
              match['anchors'] ?? const []))
            _anchorKey(match, anchor, provider: provider),
      };
      setState(() {
        sourceMatches = parsed;
        _anchorStatuses.removeWhere((key, _) => !currentKeys.contains(key));
        _anchorLineCounts.removeWhere((key, _) => !currentKeys.contains(key));
        _anchorStatusCheckedAt.removeWhere(
            (key, _) => !currentKeys.contains(key));
      });
      unawaited(
        Future<void>.delayed(Duration.zero, _probeVisibleAnchorStatuses),
      );
    } catch (e) {
      unawaited(
        AnalyticsService.capture(
          'source match list failed',
          properties: {'source': provider},
        ),
      );
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

  Future<void> _probeVisibleAnchorStatuses() async {
    if (!mounted || loading) return;

    final provider = source;
    final epoch = ++_anchorStatusEpoch;
    final matches = _visibleSourceMatches;
    final pending = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final match in matches) {
      final anchors = List<Map<String, dynamic>>.from(
        match['anchors'] ?? const [],
      );
      for (final anchor in anchors) {
        final key = _anchorKey(match, anchor, provider: provider);
        if (provider == 'cola' || provider == 'fawa') {
          // These providers have useful schedule-level status already.
          _anchorStatuses[key] = _matchLooksLive(match) ? 'live' : 'ready';
          continue;
        }

        final checked = _anchorStatusCheckedAt[key];
        if (checked != null && now.difference(checked) < _statusTtl) {
          continue;
        }
        if (pending.length >= _initialStatusProbeLimit) continue;
        _anchorStatuses[key] = 'checking';
        pending.add({'match': match, 'anchor': anchor, 'key': key});
      }
    }

    if (mounted && source == provider) setState(() {});

    for (var offset = 0; offset < pending.length; offset += 4) {
      if (!mounted || source != provider || epoch != _anchorStatusEpoch) return;

      final batch = pending.skip(offset).take(4).toList();
      await Future.wait(
        batch.map((item) async {
          final match = Map<String, dynamic>.from(item['match'] as Map);
          final anchor = Map<String, dynamic>.from(item['anchor'] as Map);
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

            final lineCount = (data['line_count'] as num?)?.toInt() ?? 0;
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
          } finally {
            // Avoid letting an older status request overwrite fresh data.
            if (mounted && source == provider && epoch == _anchorStatusEpoch) {
              _anchorStatusCheckedAt[key] = DateTime.now();
            }
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
      final time =
          DateTime.tryParse(row['match_time']?.toString() ?? '')?.toLocal();
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
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
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
                      '${englishKnownFootballName('${m['home_team']}')} vs ${englishKnownFootballName('${m['away_team']}')}',
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
                    onTap: () =>
                        Navigator.pop(sheetContext, m['id']?.toString()),
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
    bool current() => mounted && source == provider;
    if (_extractingAnchorKey != null) return;
    // A manual tap takes priority over background checking. Any queued
    // probe results become stale and cannot block the quality picker.
    ++_anchorStatusEpoch;
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
      final sourceIsLive = data is Map && _isLiveStatus(data['live_status']);
      final hasHealthy = lines.any((line) {
        final health = (line['health_status'] ?? '').toString().toLowerCase();
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

      unawaited(
        AnalyticsService.capture(
          'source lines loaded',
          properties: {
            'source': provider,
            'line_count': lines.length,
            'source_live': data is Map &&
                (data['live_status'] == true ||
                    data['live_status'] == 1 ||
                    data['live_status']?.toString() == '1'),
          },
        ),
      );

      if (!current()) return;
      if (lines.isEmpty) {
        // Only display a short, redacted source status returned by our
        // authenticated resolver. No signed URL or token is shown.
        final upstream = data is Map ? data['message']?.toString() ?? '' : '';
        final note = upstream
            .replaceAll(RegExp(r'https?://[^\s]+'), '[source]')
            .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
            .trim();
        final safeNote =
            note.length > 180 ? '${note.substring(0, 180)}…' : note;
        message(
          safeNote.isNotEmpty
              ? safeNote
              : 'No playable line is available for this streamer.',
        );
        return;
      }

      final resolvedAnchor = Map<String, dynamic>.from(anchor);
      final freshName =
          data is Map ? (data['anchor_name'] ?? '').toString().trim() : '';
      if (provider == 'yyzb' &&
          freshName.isNotEmpty &&
          _genericAnchorIdentity(anchor)) {
        // Public mirrors mask commentator names. The authenticated room
        // response can recover the legacy import name without exposing it.
        resolvedAnchor['import_name'] = freshName;
        resolvedAnchor['original_nick_name'] = freshName;
        resolvedAnchor['nick_name'] = englishSourceAnchorName(
          resolvedAnchor,
          0,
        );
      }
      await _showQualityPicker(
        match: match,
        anchor: resolvedAnchor,
        lines: lines,
        sourceLiveStatus: data is Map ? data['live_status'] : null,
      );
    } catch (e) {
      unawaited(
        AnalyticsService.capture(
          'source lines failed',
          properties: {'source': source},
        ),
      );
      if (!current()) return;
      final detail = e.toString().replaceFirst('Exception: ', '');
      message('Could not load ${_sourceLabel(provider)} stream links. $detail');
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
    final anchorName = (anchor['nick_name'] ?? 'Streamer').toString().trim();
    final importName =
        source == 'yyzb' ? _anchorImportName(anchor) : anchorName;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Stream Quality',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_sourceMatchTitle(match)} • $anchorName',
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
                                        source == 'yyzb'
                                            ? englishStreamLabel(label)
                                            : label,
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
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
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
                              await Clipboard.setData(ClipboardData(text: url));
                              unawaited(
                                AnalyticsService.capture(
                                  'source link copied',
                                  properties: {
                                    'source': source,
                                    'stream_type':
                                        (line['stream_type'] ?? 'auto')
                                            .toString(),
                                  },
                                ),
                              );
                              message('${_sourceLabel(source)} link copied.');
                            },
                            icon: const Icon(Icons.copy_rounded),
                          ),
                          FilledButton(
                            onPressed: () async {
                              final added = await _addLine(
                                line: line,
                                anchorName: importName,
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
    setState(() => _addingLine = true);
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
              ...sourceLineKeyFields(line),
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
                ...sourceLineKeyFields(line),
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
                ...sourceLineKeyFields(line),
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
      unawaited(
        AnalyticsService.capture(
          'source line imported',
          properties: {
            'source': provider,
            'stream_type': type,
            'resolution': resolution,
            'destination_preset': presetTarget != null,
            'health_status': 'pending',
          },
        ),
      );

      final shownLabel = provider == 'yyzb' ? englishStreamLabel(label) : label;
      message('$sourceName $shownLabel added. Health check is pending.');
      return true;
    } on TimeoutException {
      message('Could not confirm the save. Refresh before trying again.');
      return false;
    } catch (_) {
      message('Could not add the server. Please retry.');
      return false;
    } finally {
      if (mounted) {
        setState(() => _addingLine = false);
      } else {
        _addingLine = false;
      }
    }
  }

  Future<void> _checkSavedLine(String id, String provider) async {
    try {
      final checked = await FunctionGateway.invoke(
        'stream-health',
        body: {'link_id': id},
      ).timeout(const Duration(seconds: 12));
      unawaited(
        AnalyticsService.capture(
          'stream health checked',
          properties: {
            'scope': 'link',
            'source': provider,
            if (checked is Map && checked['health_status'] != null)
              'health_status': checked['health_status'].toString(),
          },
        ),
      );
    } catch (_) {
      // System Health and Stream Servers show the eventual persisted result.
      // Do not show an error on a newer source/destination screen.
    }
  }

  String? nullable(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _refreshLibrary() {
    if (!mounted) return;
    setState(() => _libraryFuture = _streamLibrary.list());
  }

  Future<void> _saveHlsToLibrary() async {
    if (_savingLibrary) return;
    final url = _playzUrl.text.trim();
    final inferred = detectManualStreamType(url);
    final type = _playzType == 'auto' ? inferred : _playzType;
    if (type != 'hls') {
      message('Only HLS / M3U8 can be saved to the Library.');
      return;
    }

    final name = _playzServerName.text.trim().isEmpty
        ? 'Server 1'
        : _playzServerName.text.trim();
    final validation = validateHlsLibraryInput(
      label: name,
      streamUrl: url,
      referer: _playzReferer.text,
      origin: _playzOrigin.text,
    );
    if (validation != null) {
      message(validation);
      return;
    }

    setState(() => _savingLibrary = true);
    try {
      await _streamLibrary.save(
        label: name,
        streamUrl: url,
        referer: _playzReferer.text,
        origin: _playzOrigin.text,
      );
      unawaited(
        AnalyticsService.capture(
          'stream library saved',
          properties: const {'stream_type': 'hls'},
        ),
      );
      _refreshLibrary();
      message('$name saved to the private HLS Library.');
    } on TimeoutException {
      message('Library save timed out. Refresh before trying again.');
    } catch (_) {
      message('Could not save this HLS entry. Please retry.');
    } finally {
      if (mounted) setState(() => _savingLibrary = false);
    }
  }

  void _useLibraryEntry(StreamLibraryEntry entry) {
    setState(() {
      _playzServerName.text = entry.label;
      _playzUrl.text = entry.streamUrl;
      _playzReferer.text = entry.referer ?? '';
      _playzOrigin.text = entry.origin ?? '';
      _playzKeyId.clear();
      _playzKeyData.clear();
      _playzType = 'hls';
    });
    message('${entry.label} loaded into the manual form.');
  }

  Future<void> _addLibraryEntry(StreamLibraryEntry entry) async {
    final added = await _addLine(
      anchorName: 'Library',
      line: entry.toPlaybackLine(),
    );
    if (!added) return;
    unawaited(
      _streamLibrary.markUsed(entry.id).then((_) {
        if (mounted) _refreshLibrary();
      }).catchError((_) {}),
    );
  }

  Future<void> _deleteLibraryEntry(StreamLibraryEntry entry) async {
    if (_deletingLibraryId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete saved HLS?'),
        content: Text(
          'Delete “${entry.label}” from the private Library? '
          'Lines already added to matches will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingLibraryId = entry.id);
    try {
      await _streamLibrary.delete(entry.id);
      _refreshLibrary();
      message('${entry.label} removed from the Library.');
    } catch (_) {
      message('Could not delete this Library entry.');
    } finally {
      if (mounted) setState(() => _deletingLibraryId = null);
    }
  }

  Future<void> _addManualLine() async {
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

    final keyId = _playzKeyId.text.trim();
    final keyData = _playzKeyData.text.trim();
    final keyError = manualClearKeyError(
      streamType: type,
      keyId: keyId,
      keyData: keyData,
    );
    if (keyError != null) {
      message(keyError);
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
        'key_id': keyId,
        'key_data': keyData,
      },
    );
    if (added && mounted) {
      setState(() {
        _playzServerName.text = 'Server 1';
        _playzUrl.clear();
        _playzReferer.clear();
        _playzOrigin.clear();
        _playzKeyId.clear();
        _playzKeyData.clear();
        _playzType = 'auto';
      });
    }
  }

  Widget _streamLibrarySection(ColorScheme colors) {
    _libraryFuture ??= _streamLibrary.list();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private HLS Library',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 2),
                  Text('Admin-only · URL query and keys are never shown'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh Library',
              onPressed: _refreshLibrary,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<StreamLibraryEntry>>(
          future: _libraryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Could not load the private Library. Tap refresh to retry.',
                  style: TextStyle(color: colors.error),
                ),
              );
            }
            final entries = snapshot.data ?? const <StreamLibraryEntry>[];
            if (entries.isEmpty) {
              return Text(
                'No saved HLS yet. Enter an authorized M3U8 URL above and tap SAVE HLS.',
                style: TextStyle(color: colors.onSurfaceVariant),
              );
            }

            return Column(
              children: entries.map((entry) {
                final deleting = _deletingLibraryId == entry.id;
                return Card.outlined(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.video_library_outlined,
                              size: 22,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                entry.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const Text(
                              'HLS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          safeStreamLocation(entry.streamUrl),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: deleting
                                  ? null
                                  : () => _useLibraryEntry(entry),
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                              ),
                              label: const Text('USE'),
                            ),
                            FilledButton.icon(
                              onPressed: deleting || _addingLine
                                  ? null
                                  : () => _addLibraryEntry(entry),
                              icon: const Icon(
                                Icons.add_link_rounded,
                                size: 18,
                              ),
                              label: const Text('ADD TO MATCH'),
                            ),
                            IconButton(
                              tooltip: 'Delete saved HLS',
                              onPressed: deleting
                                  ? null
                                  : () => _deleteLibraryEntry(entry),
                              icon: deleting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(growable: false),
            );
          },
        ),
      ],
    );
  }

  Widget _manualSourceCard(ColorScheme colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_sourceLabel(source)} · Manual stream',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste only a direct stream URL you are authorized to use. '
              'HLS / M3U8 can be saved in your private Library for reuse. '
              'This does not extract links from an APK or bypass app/DRM access.',
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
            if (_playzType == 'dash') ...[
              const SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Optional DASH ClearKey'),
                subtitle: const Text(
                  'Use only keys you are authorized to use.',
                ),
                children: [
                  TextField(
                    controller: _playzKeyId,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Key ID (KID)',
                      hintText: '00112233445566778899aabbccddeeff',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _playzKeyData,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Key Data',
                      hintText: 'ffeeddccbbaa99887766554433221100',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Both values must contain 32 hexadecimal characters. '
                    'They are saved with the stream record, not bundled into the APK.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _savingLibrary ? null : _saveHlsToLibrary,
                  icon: _savingLibrary
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bookmark_add_outlined),
                  label: const Text('SAVE HLS'),
                ),
                FilledButton.icon(
                  onPressed: _addingLine ? null : _addManualLine,
                  icon: _addingLine
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_link_rounded),
                  label: const Text('ADD TO NCA MATCH'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'You must confirm the destination match before saving. '
              'A reachability check follows; successful playback is not guaranteed.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            _streamLibrarySection(colors),
          ],
        ),
      ),
    );
  }

  String _anchorImportName(Map<String, dynamic> anchor) {
    // Presentation can change, but legacy signed-URL imports match this raw
    // identity. Renaming it would create a second row on the next refresh.
    for (final field in ['import_name', 'original_nick_name', 'nick_name']) {
      final name = anchor[field]?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return 'Streamer';
  }

  bool _genericAnchorIdentity(Map<String, dynamic> anchor) {
    final generic = RegExp(
      r'^(?:YYZB\s+)?(?:Server|Streamer)\s*\d*(?:\s*\((?:Cantonese|Mandarin)\))?$',
      caseSensitive: false,
    );
    return ['import_name', 'original_nick_name', 'nick_name'].every((field) {
      final name = anchor[field]?.toString().trim() ?? '';
      return name.isEmpty || generic.hasMatch(name);
    });
  }

  String _sourceMatchTitle(Map<String, dynamic> match) {
    final home = (match['home_team'] ?? '').toString();
    return '$home vs ${match['away_team'] ?? ''}';
  }

  String _sourceLabel(String value) {
    switch (value) {
      case 'playz':
        return 'Manual HLS Library';
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

  Widget _dayButton(String value, String label) {
    final selected = dayFilter == value;

    void selectDay() {
      setState(() => dayFilter = value);
      unawaited(
        Future<void>.delayed(Duration.zero, _probeVisibleAnchorStatuses),
      );
    }

    return selected
        ? FilledButton.tonal(onPressed: selectDay, child: Text(label))
        : TextButton(onPressed: selectDay, child: Text(label));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _visibleSourceMatches;

    return Scaffold(
      appBar: AppBar(
        title: Text(_sourceLabel(source)),
        actions: [
          IconButton(
            tooltip: 'Refresh source',
            onPressed: loading || _isManualSource ? null : _loadSoco,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSoco,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
                if (_isManualSource) _manualSourceCard(colors),
                if (!_isManualSource)
                  SwitchListTile.adaptive(
                    value: availableOnly,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      'Available only',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('Hide matches that have no source yet.'),
                    onChanged: (value) => setState(() => availableOnly = value),
                  ),
                const SizedBox(height: 4),
                if (!_isManualSource &&
                    source != 'fawa' &&
                    source != 'cola')
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
                if (!_isManualSource &&
                    !loading &&
                    visible.isEmpty &&
                    errorText == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'No football matches in this source section.',
                      ),
                    ),
                  ),
                ...visible.map((match) {
                  final kickoff = DateTime.tryParse(
                    match['match_time']?.toString() ?? '',
                  )?.toLocal();
                  final anchors = List<Map<String, dynamic>>.from(
                    match['anchors'] ?? const [],
                  )..sort((a, b) {
                      final aStatus = _anchorStatuses[_anchorKey(match, a)];
                      final bStatus = _anchorStatuses[_anchorKey(match, b)];
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
                            _sourceMatchTitle(match),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            match['kind'] == 'channel'
                                ? 'Broadcast channel'
                                : kickoff == null
                                    ? 'Unknown time'
                                    : DateFormat(
                                        'dd MMM • h:mm a',
                                        'en_US',
                                      ).format(kickoff),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          if (anchors.isEmpty)
                            Text(
                              'No streamer is listed yet.',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: anchors.map((anchor) {
                                final name = (anchor['nick_name'] ?? 'Streamer')
                                    .toString();
                                final key = _anchorKey(match, anchor);
                                final status =
                                    _anchorStatuses[key] ?? 'unknown';
                                final lineCount = _anchorLineCounts[key] ?? 0;

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

                                final extracting = _extractingAnchorKey == key;

                                return OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: color,
                                    side: BorderSide(
                                      color: color.withValues(alpha: .55),
                                    ),
                                  ),
                                  onPressed: _extractingAnchorKey != null
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
          ),
    );
  }
}
