import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../football_english.dart';
import '../services/manual_source_url.dart';
import '../services/admin_web_source_cache.dart';
import '../services/function_gateway.dart';
import '../services/stream_library_service.dart';
import '../source_line_validation.dart';
import '../source_match_search.dart';
import '../services/myanmar_time.dart';
import '../services/source_match_suggestions.dart';
import '../services/source_import_service.dart';
import '../services/source_resolution_cache.dart';
import '../services/match_paging.dart';
import '../widgets/source_quality_sheet.dart';
import '../widgets/match_destination_sheet.dart';
import 'live_links_page.dart';
import 'stream_preview_page.dart';
import '../services/stream_detector_service.dart';
import '../services/website_detector_service.dart';
import '../source_room_status.dart';
import 'stream_detector_page.dart'
    if (dart.library.html) 'stream_detector_page_web.dart';

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

/// A user-initiated browser fallback for the publisher-linked CricHD player.
/// This does not access protected media, reuse browser verification or prove HLS.
@visibleForTesting
Uri? cricHdBrowserPlayerPage(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final page = Uri.tryParse(text);
  if (page == null ||
      page.scheme != 'https' ||
      page.userInfo.isNotEmpty ||
      (page.hasPort && page.port != 443) ||
      !const {'playerbee.top', 'www.playerbee.top'}.contains(page.host) ||
      page.pathSegments.isEmpty) {
    return null;
  }
  return page;
}

/// Prefer the exact published watch link the operator tapped. Never switch
/// between CricHD Link 1 and Link 2 when the backend cannot read a player.
@visibleForTesting
Uri? cricHdQuickDetectPlayer(Map<String, dynamic> anchor, dynamic response) {
  final selected = anchor['watch_url']?.toString();
  if (selected != null && selected.trim().isNotEmpty) {
    return cricHdBrowserPlayerPage(selected);
  }
  return response is Map
      ? cricHdBrowserPlayerPage(response['browser_player_url']?.toString())
      : null;
}

@visibleForTesting
bool sourceStatusIsFresh(DateTime? checkedAt, DateTime now,
    {Duration ttl = const Duration(minutes: 2)}) {
  return checkedAt != null &&
      !checkedAt.isAfter(now) &&
      now.difference(checkedAt) < ttl;
}

@visibleForTesting
Future<void> runBoundedStatusChecks<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) check,
) async {
  if (items.isEmpty) return;
  var next = 0;
  final workerCount = concurrency.clamp(1, items.length).toInt();

  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      await check(item);
    }
  }

  await Future.wait(List.generate(workerCount, (_) => worker()));
}

/// Bound private pages must not accept results after sign-out or account
/// switch. On Web, session generation also rejects same-user relogin races.
@visibleForTesting
bool sourceSessionMatches({
  required String? pageUser,
  required String? activeUser,
  required int pageGeneration,
  required int currentGeneration,
  required bool isWeb,
}) =>
    pageUser != null &&
    activeUser == pageUser &&
    pageGeneration == currentGeneration;

class SocoImportPage extends StatefulWidget {
  const SocoImportPage({
    super.key,
    this.initialMatchId,
    this.initialSource = 'soco',
    this.initialReferer,
    this.onMutated,
  });

  /// Called only after a confirmed successful source-line mutation.
  final VoidCallback? onMutated;
  final String? initialMatchId;
  final String initialSource;
  final String? initialReferer;

  @override
  State<SocoImportPage> createState() => _SocoImportPageState();
}

class _SocoImportPageState extends State<SocoImportPage> {
  static const _experimentalSourceNames = <String, String>{
    'roxie': 'RoxieStreams',
    'crichd': 'CricHD',
  };
  bool get _isExperimentalSource =>
      _experimentalSourceNames.containsKey(source);
  bool get _isManualSource => source == 'playz';
  bool get _currentSession => sourceSessionMatches(
        pageUser: _sourceSessionUserId,
        activeUser: Supabase.instance.client.auth.currentSession?.user.id,
        pageGeneration: _sourceSessionGeneration,
        currentGeneration: AdminWebSourceCache.sessionGeneration,
        isWeb: kIsWeb,
      );

  static const _pagesMirrorBase =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources';
  static const _rawMirrorBase =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/sources';

  static final bool _enableNoVpnFallback = const String.fromEnvironment(
        'ENABLE_NO_VPN_FALLBACK',
        defaultValue: '0',
      ).trim() ==
      '1';
  late final SourceImportService _importer =
      SourceImportService(Supabase.instance.client);
  Map<String, dynamic>? _destinationSourceMatch;
  Map<String, dynamic> _importRoom = const {};
  int _extractionGeneration = 0;
  String? targetMatchId;
  bool loading = false;
  bool availableOnly = false;
  String source = 'soco';
  String _crichdSport = 'football';
  String _combatCategory = 'all';
  bool get _crichdCombat => source == 'crichd' && _crichdSport == 'combat';
  String dayFilter = 'today';
  String? errorText;
  String? _experimentalEmptyReason;

  String? _explainExperimentalResponse(dynamic data) {
    if (data is! Map || data['diagnostics'] is! Map) return null;
    final diagnostics = data['diagnostics'] as Map;
    if (data['sport'] == 'combat') {
      if (diagnostics['content_state'] ==
          'source_unavailable_or_verification_required') {
        return 'CricHD schedule could not be read or needs browser verification. No events or lines were invented.';
      }
      return 'No published events for this combat category on CricHD right now. Categories without a published section are unavailable.';
    }
    final found = (diagnostics['candidate_count'] as num?)?.toInt() ?? 0;
    final confirmed =
        (diagnostics['confirmed_kickoff_count'] as num?)?.toInt() ?? 0;
    final estimated =
        (diagnostics['estimated_countdown_count'] as num?)?.toInt() ?? 0;
    final scheduleOnly =
        (diagnostics['schedule_only_count'] as num?)?.toInt() ?? 0;
    if (found > 0) {
      return '$found football fixture(s) found • $confirmed timed, $estimated estimated from fresh countdown. '
          '$scheduleOnly schedule-only fixtures have no playback links. '
          'A fixture does not guarantee video playback.';
    }
    return switch (diagnostics['content_state']?.toString()) {
      'browser_render_or_unsupported_markup' =>
        'No fixture data found in public HTML or embedded JSON. '
            'This site may load matches through browser JavaScript; a permitted '
            'public data endpoint is needed. No video stream is verified.',
      'no_recognized_football_fixtures' =>
        'No verified football fixtures are currently available from this source. '
            'The page returned JSON, but it did not contain a confirmed football '
            'match with recognizable teams and a trusted event page. It may be '
            'showing configuration or loading fixtures in the browser instead. '
            'No match or playable video link has been invented.',
      'empty_page' =>
        'This source currently has no verified football fixtures on its public page.',
      _ => 'No verified football event was returned by this provider.',
    };
  }

  final _sourceSearch = TextEditingController();
  late final ScrollController _sourceScroll;
  String _sourceQuery = '';
  List<Map<String, dynamic>> sourceMatches = const [];
  final Map<String, String> _anchorStatuses = <String, String>{};
  final Map<String, int> _anchorLineCounts = <String, int>{};
  // Status is advisory, not a prerequisite for tapping a stream source.
  final Map<String, DateTime> _anchorStatusCheckedAt = <String, DateTime>{};
  static const _statusTtl = Duration(minutes: 2);
  // Check every visible room, but cap simultaneous resolver work so one slow
  // upstream cannot serialize the whole page or overload the gateway.
  static const _statusProbeConcurrency = 12;
  int _anchorStatusEpoch = 0;
  String? _extractingAnchorKey;
  Timer? _sourceRefreshTimer;
  bool _backgroundRefreshBusy = false;
  int _sourceLoadEpoch = 0;
  late final int _sourceSessionGeneration;
  late final String? _sourceSessionUserId;
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
    _sourceSessionUserId =
        Supabase.instance.client.auth.currentSession?.user.id;
    AdminWebSourceCache.bindUser(_sourceSessionUserId);
    _sourceSessionGeneration = AdminWebSourceCache.sessionGeneration;
    SourceResolutionCache.bind(_sourceSessionUserId);
    targetMatchId = widget.initialMatchId ?? AdminWebSourceCache.recentMatchId;
    if (widget.initialReferer != null) {
      _playzReferer.text = widget.initialReferer!;
      final page = Uri.tryParse(widget.initialReferer!);
      if (page != null) _playzOrigin.text = page.origin;
    }
    final requested = widget.initialSource.trim().toLowerCase();
    source = (_experimentalSourceNames.containsKey(requested) ||
            const {
              'soco',
              'yyzb',
              'fawa',
              'cola',
              'arena',
              'playz',
            }.contains(requested))
        ? requested
        : 'soco';
    if (source == 'arena') availableOnly = false;
    if (_isManualSource) _libraryFuture = _streamLibrary.list();
    dayFilter = (source == 'fawa' ||
            source == 'cola' ||
            source == 'arena' ||
            _isExperimentalSource ||
            _isManualSource)
        ? 'all'
        : 'today';
    final ui = AdminWebSourceCache.ui(source);
    if (!_isManualSource) {
      _sourceQuery = ui.query;
      _sourceSearch.text = ui.query;
      dayFilter =
          (source == 'fawa' || _isExperimentalSource) ? 'all' : ui.dayFilter;
      availableOnly = _isExperimentalSource ? false : ui.availableOnly;
      sourceMatches = AdminWebSourceCache.rows(source) ?? const [];
    }
    _sourceScroll = ScrollController(initialScrollOffset: ui.scrollOffset);
    if (sourceMatches.isEmpty && !AdminWebSourceCache.fresh(source)) {
      unawaited(_loadSoco());
    } else if (!AdminWebSourceCache.fresh(source)) {
      unawaited(_loadSoco(silent: true));
    }
    _sourceRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshSourceInBackground()),
    );
  }

  @override
  void dispose() {
    _sourceLoadEpoch += 1;
    _sourceRefreshTimer?.cancel();
    if (!_isManualSource && _currentSession) {
      AdminWebSourceCache.saveUi(
          source,
          AdminSourceUiState(
            query: _sourceQuery,
            dayFilter: dayFilter,
            availableOnly: availableOnly,
            scrollOffset: _sourceScroll.hasClients ? _sourceScroll.offset : 0,
          ));
    }
    _sourceScroll.dispose();
    _sourceSearch.dispose();
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
    if (!_currentSession || AdminWebSourceCache.fresh(source)) return;
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
    final data = await loadAdminMatches(Supabase.instance.client,
        columns:
            'id,league,home_team,away_team,kickoff_at,sort_order,is_live,is_active,is_finished,is_featured,publish_state,deleted_at',
        activeOnly: true,
        publishedOnly: true);

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
    final isCombat = _crichdCombat;
    final category = _combatCategory;
    final requestBody = <String, dynamic>{
      'source': provider,
      if (isCombat) 'sport': 'combat',
      if (isCombat) 'category': category
    };
    final cacheKey = isCombat ? 'crichd-combat-$category' : provider;
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
    final sessionGeneration = AdminWebSourceCache.sessionGeneration;
    bool current() =>
        mounted &&
        source == provider &&
        epoch == _sourceLoadEpoch &&
        (sessionGeneration == _sourceSessionGeneration && _currentSession);
    if (!silent) {
      setState(() {
        loading = true;
        errorText = null;
      });
    }

    try {
      String? loadDiagnostic;
      final parsed = await AdminWebSourceCache.load(cacheKey, () async {
        dynamic data;
        if (!_enableNoVpnFallback || isCombat) {
          data = await FunctionGateway.invoke(
            'source-match-list',
            body: requestBody,
          );
          validateSourceMatchRows(data, provider);
        } else {
          try {
            data = await FunctionGateway.invoke(
              'source-match-list',
              body: requestBody,
            );
            validateSourceMatchRows(data, provider);
          } catch (_) {
            data = await _loadSourceMirror(provider);
            validateSourceMatchRows(data, provider);
          }
        }

        final rows = validateSourceMatchRows(data, provider);
        if (_experimentalSourceNames.containsKey(provider)) {
          loadDiagnostic = _explainExperimentalResponse(data);
        }

        final parsed = rows
            .map((row) => englishSourceMatch(row, provider))
            .where((row) =>
                provider != 'yyzb' ||
                (row['anchors'] is List &&
                    (row['anchors'] as List).any((anchor) =>
                        anchor is Map &&
                        (anchor['room_num']?.toString().trim().isNotEmpty ??
                            false))))
            .where((row) => isCombat || !_staleSourceMatch(row))
            .toList();

        parsed.sort((a, b) => compareAdminSourceMatches(a, b, provider));
        return parsed;
      }, force: true);

      unawaited(
        AnalyticsService.capture(
          'source match list loaded',
          properties: {'source': provider, 'match_count': parsed.length},
        ),
      );
      if (!current()) return;
      // A one-minute background catalog refresh must not reset all streamer
      // statuses and trigger an identical network probe storm.
      if (silent &&
          jsonEncode(sourceMatches) == jsonEncode(parsed) &&
          _experimentalEmptyReason == loadDiagnostic) {
        // Keep the catalog without repainting. Only TTL-expired statuses
        // are rechecked; unchanged results never trigger a full probe storm.
        unawaited(
          Future<void>.delayed(Duration.zero, _probeVisibleAnchorStatuses),
        );
        return;
      }
      final currentKeys = <String>{
        for (final match in parsed)
          for (final anchor
              in List<Map<String, dynamic>>.from(match['anchors'] ?? const []))
            _anchorKey(match, anchor, provider: provider),
      };
      setState(() {
        sourceMatches = parsed;
        _experimentalEmptyReason = loadDiagnostic;
        _anchorStatuses.removeWhere((key, _) => !currentKeys.contains(key));
        _anchorLineCounts.removeWhere((key, _) => !currentKeys.contains(key));
        _anchorStatusCheckedAt
            .removeWhere((key, _) => !currentKeys.contains(key));
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
          if (sourceMatches.isEmpty) {
            sourceMatches = const [];
          }
          errorText =
              'Could not refresh ${_sourceLabel(provider)} sources. $detail';
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
    if (!mounted || loading || !_currentSession) return;

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
        if (_matchLooksLive(match)) {
          // Paint known-live schedule rows immediately; no network round trip
          // is needed before the operator can see the red LIVE badge.
          _anchorStatuses[key] = 'live';
          _anchorStatusCheckedAt[key] = now;
          continue;
        }
        if (_experimentalSourceNames.containsKey(provider)) {
          // No automatic HTML polling for experimental third-party sites.
          // Only a direct operator tap requests the page's media list.
          _anchorStatuses[key] = 'unknown';
          _anchorStatusCheckedAt[key] = now;
          continue;
        }
        if (provider == 'fawa') {
          // Fawa has useful schedule-level readiness metadata. Soco, YYZB
          // and Cola are resolved below because their room state can change.
          _anchorStatuses[key] = _matchLooksLive(match) ? 'live' : 'ready';
          _anchorStatusCheckedAt[key] = now;
          continue;
        }

        final checked = _anchorStatusCheckedAt[key];
        if (sourceStatusIsFresh(checked, now, ttl: _statusTtl)) {
          continue;
        }
        _anchorStatuses[key] = _matchLooksLive(match) ? 'live' : 'checking';
        pending.add({'match': match, 'anchor': anchor, 'key': key});
      }
    }

    if (mounted && source == provider && _currentSession) setState(() {});

    await runBoundedStatusChecks(
      pending,
      _statusProbeConcurrency,
      (item) async {
        if (!mounted ||
            !_currentSession ||
            source != provider ||
            epoch != _anchorStatusEpoch) return;
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

          if (!mounted ||
              !_currentSession ||
              source != provider ||
              epoch != _anchorStatusEpoch) return;
          if (data is! Map) {
            _anchorStatuses[key] = _matchLooksLive(match) ? 'live' : 'unknown';
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
          if (_currentSession) _anchorStatuses[key] = 'unknown';
        } finally {
          // Avoid letting an older status request overwrite fresh data.
          if (mounted &&
              _currentSession &&
              source == provider &&
              epoch == _anchorStatusEpoch) {
            _anchorStatusCheckedAt[key] = DateTime.now();
          }
          // Repaint this room as soon as its own request finishes. A slow
          // neighbour no longer holds the whole four-item batch at UNKNOWN.
          if (mounted &&
              _currentSession &&
              source == provider &&
              epoch == _anchorStatusEpoch) {
            setState(() {});
          }
        }
      },
    );
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
    Iterable<Map<String, dynamic>> rows = sourceMatches.where(
      (row) => sourceMatchMatchesQuery(row, _sourceQuery),
    );

    if (availableOnly) {
      rows = rows.where((row) {
        final anchors = row['anchors'];
        return anchors is List && anchors.isNotEmpty;
      });
    }

    if (source == 'fawa' || source == 'cola' || dayFilter == 'all') {
      return rows.toList();
    }

    // Source cards and date filters use the same Myanmar calendar.
    const mmOffset = Duration(hours: 6, minutes: 30);
    final now = DateTime.now().toUtc().add(mmOffset);
    final wanted = dayFilter == 'tomorrow'
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    return rows.where((row) {
      final parsed = DateTime.tryParse(row['match_time']?.toString() ?? '');
      final time = parsed == null ? null : parsed.toUtc().add(mmOffset);
      return time != null && _sameDate(time, wanted);
    }).toList();
  }

  Future<String?> _chooseDestination() async {
    final loaded = await _loadTargetMatches();
    if (!mounted) return null;
    if (loaded.isEmpty) {
      message(
          'No active NCA match is available. Create or publish a match in Controls first.');
      return null;
    }

    final targets = suggestDestinations(loaded, _destinationSourceMatch,
        preferred: targetMatchId);
    return showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => MatchDestinationSheet(matches: targets));
  }

  Future<void> _openSourceDetector(
      Map<String, dynamic> match, Map<String, dynamic> anchor, String provider,
      {bool quickHls = false, String? playerUrl}) async {
    if (!mounted || !_currentSession || source != provider) return;
    final url = (playerUrl ??
            (source == 'crichd'
                ? (anchor['watch_url'] ??
                    anchor['page_url'] ??
                    match['page_url'])
                : (anchor['page_url'] ?? match['page_url'])))
        .toString()
        .trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (quickHls &&
            (provider != 'crichd' || cricHdBrowserPlayerPage(url) == null))) {
      message('This source has not published a player page URL.');
      return;
    }
    final selected = await Navigator.of(context).push<Object>(MaterialPageRoute(
      settings: const RouteSettings(name: '/admin/stream-detector'),
      builder: (_) => StreamDetectorPage(
        initialUrl: url,
        selectionMode: true,
        autoSelectHls: quickHls,
        qualityMode: quickHls,
      ),
    ));
    if (selected == null || !mounted || !_currentSession || source != provider)
      return;
    final streams = selected is DetectedStream
        ? [selected]
        : selected is List
            ? selected.whereType<DetectedStream>().toList()
            : <DetectedStream>[];
    if (streams.isEmpty) return;
    final lines = [
      for (final stream in streams)
        <String, dynamic>{
          'url': stream.url,
          'stream_type': stream.type,
          'referer': stream.referer,
          'origin': stream.origin,
          'label': '${_sourceLabel(provider)} · ${stream.type.toUpperCase()}',
          'resolution': 'Auto',
          'health_status': 'unknown',
          'discovery_mode': 'source_browser',
        }
    ];
    final key = _anchorKey(match, anchor, provider: provider);
    setState(() {
      _anchorLineCounts[key] = lines.length;
      _anchorStatuses[key] = 'detected';
    });
    _importRoom = {
      'room_num': anchor['room_num'],
      'schedule_id': match['schedule_id'],
      'page_url': anchor['page_url'] ?? match['page_url'],
      'watch_url': anchor['watch_url']
    };
    await _showQualityPicker(match: match, anchor: anchor, lines: lines);
  }

  Future<void> _openAnchor(
      Map<String, dynamic> match, Map<String, dynamic> anchor,
      {bool force = false}) async {
    final room = anchor['room_num']?.toString().trim() ?? '';
    if (room.isEmpty) return;

    final extractingKey = _anchorKey(match, anchor);
    final provider = source;
    if (_extractingAnchorKey != null) return;
    final extractionEpoch = ++_extractionGeneration;
    bool current() =>
        mounted &&
        _currentSession &&
        source == provider &&
        extractionEpoch == _extractionGeneration;
    // A manual tap takes priority over background checking. Any queued
    // probe results become stale and cannot block the quality picker.
    ++_anchorStatusEpoch;
    setState(() => _extractingAnchorKey = extractingKey);

    try {
      _importRoom = {
        'room_num': room,
        'schedule_id': match['schedule_id'],
        'page_url': anchor['page_url'] ?? match['page_url'],
        'watch_url': anchor['watch_url']
      };
      final dynamic data =
          await SourceResolutionCache.load(provider, _importRoom, () async {
        final resolved = await FunctionGateway.invoke(
          'soco-links',
          body: {
            'action': 'streams',
            'source': provider,
            'room_num': room,
            'schedule_id': match['schedule_id'],
            'page_url': anchor['page_url'] ?? match['page_url'],
            if (provider == 'crichd') 'watch_url': anchor['watch_url'],
            // Cola URLs are checked before the operator can import them.
            // Other rotating providers keep the fast metadata-only path.
            'skip_probe': provider != 'cola' && !_isExperimentalSource,
            // These sources return unverified public candidates promptly;
            // don't wait for repeated server probes on an explicit tap.
            if (provider == 'crichd' || provider == 'roxie')
              'preview_only': true,
          },
        );
        if (resolved is! Map)
          throw const FormatException('Invalid source response');
        return Map<String, dynamic>.from(resolved);
      }, force: force);

      final rows = data is Map ? data['lines'] : null;
      if (!current()) return;
      if (rows is! List) {
        throw const FormatException('No stream quality list returned.');
      }

      var lines = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => (row['url'] ?? '').toString().trim().isNotEmpty)
          .toList();
      // CricHD: reuse the on-device browser session for bounded discovery.
      // Show verification/Play only when interaction is needed; verified
      // playlists return to the same Copy/ADD quality cards.
      if (provider == 'crichd' && !kIsWeb && lines.isEmpty) {
        final selectedPlayer = cricHdQuickDetectPlayer(anchor, data);
        if (selectedPlayer != null) {
          await _openSourceDetector(match, anchor, provider,
              quickHls: true, playerUrl: selectedPlayer.toString());
          return;
        }
      }
      // A deliberate CricHD match tap may inspect the publisher's public
      // Watch page when plain HTML does not expose HLS. Browser Run is
      // admin-authorized, bounded and URL-only: no cookies, DRM keys or
      // access-control workarounds. Other providers are unchanged.
      // PlayerBee may refuse server-side requests with 401/403 even when
      // the user's browser can play. Avoid a redundant browser scan after
      // a definite denial; keep the manual DETECT action available.
      final playerDenied = data is Map &&
          data['diagnostics'] is Map &&
          (data['diagnostics'] as Map)['access_denied'] == true;
      if (provider == 'crichd' &&
          lines.isEmpty &&
          data is Map &&
          !playerDenied) {
        final page = (data['browser_player_url'] ?? '').toString();
        final target = Uri.tryParse(page);
        if (target != null &&
            target.scheme == 'https' &&
            const {'playerbee.top', 'www.playerbee.top'}
                .contains(target.host) &&
            target.userInfo.isEmpty) {
          try {
            final scan =
                await const WebsiteDetectorService().scan(page, browser: true);
            if (!current()) return;
            lines = scan.links
                .where((item) => item['type'] == 'hls')
                .map((item) => <String, dynamic>{
                      'url': item['url'] ?? '',
                      'stream_type': 'hls',
                      // PlayerBee publishes origin-only Referer policy
                      // for cross-site media requests (observed in DevTools).
                      'referer': '${target.origin}/',
                      'origin': target.origin,
                      'label': 'CricHD • HLS',
                      'resolution': 'Auto',
                      'health_status': 'unknown',
                      'discovery_mode': 'source_browser',
                    })
                .toList();
          } catch (_) {
            // Browser Run may be unavailable or the publisher may deny
            // the visit. The existing DETECT/manual flow stays intact.
          }
        }
      }
      final statusKey = _anchorKey(match, anchor, provider: provider);
      final sourceIsLive = data is Map && _isLiveStatus(data['live_status']);
      final hasHealthy = lines.any((line) {
        final health = (line['health_status'] ?? '').toString().toLowerCase();
        return health == 'healthy' || health == 'slow';
      });
      if (current()) {
        setState(() {
          _anchorLineCounts[statusKey] = lines.length;
          _anchorStatuses[statusKey] = sourceRoomStatusFromLines(
            provider: provider,
            isLive: sourceIsLive,
            hasHealthy: hasHealthy,
            lineCount: lines.length,
          );
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
      // A server-side 401/403 does not establish whether the operator's
      // own browser can load the player. Open the consent-gated network
      // detector directly, never a video player or an automated challenge.
      // The detector reports only permitted 2xx media responses.
      if (provider == 'crichd' && playerDenied && lines.isEmpty) {
        final browserPage =
            cricHdBrowserPlayerPage(data['browser_player_url']?.toString());
        if (browserPage != null) {
          await _openSourceDetector(match, anchor, provider);
          return;
        }
      }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(safeNote.isNotEmpty
              ? safeNote
              : 'No native video line was resolved.'),
          action: (_isExperimentalSource &&
                  (anchor['page_url'] ?? match['page_url']) != null)
              ? SnackBarAction(
                  label: 'DETECT',
                  onPressed: () => _openSourceDetector(match, anchor, provider))
              : null,
        ));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Could not load ${_sourceLabel(provider)} stream links. $detail'),
        action: (_isExperimentalSource &&
                (anchor['page_url'] ?? match['page_url']) != null)
            ? SnackBarAction(
                label: 'DETECT',
                onPressed: () => _openSourceDetector(match, anchor, provider))
            : null,
      ));
    } finally {
      if (current() && _extractingAnchorKey == extractingKey) {
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
    final provider = source;
    final anchorName = source == 'yyzb'
        ? _anchorImportName(anchor)
        : (anchor['nick_name'] ?? 'Streamer').toString();
    _destinationSourceMatch = match;
    if (mounted) setState(() => _extractingAnchorKey = null);
    await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SourceQualitySheet(
              title:
                  '${_sourceMatchTitle(match)} • ${provider == 'yyzb' ? englishSourceAnchorName(anchor, 0) : anchorName}',
              lines: lines,
              onAdd: (selected) async {
                if (!_currentSession || source != provider) return null;
                return _addLines(selected, anchorName);
              },
              onRefresh: () {
                Navigator.pop(sheet);
                _extractingAnchorKey = null;
                unawaited(_openAnchor(match, anchor, force: true));
              },
              onTest: (line) => Navigator.of(sheet).push<void>(
                  MaterialPageRoute(
                      builder: (_) => StreamPreviewPage(
                          stream: DetectedStream(
                              url: '${line['url']}',
                              type: '${line['stream_type'] ?? 'auto'}',
                              referer: '${line['referer'] ?? ''}',
                              origin: '${line['origin'] ?? ''}')))),
              onOpenMatch: (id) {
                Navigator.pop(sheet);
                Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => LiveLinksPage(initialMatchId: id)));
              },
            ));
  }

  Future<Map<String, dynamic>?> _addLines(
      List<Map<String, dynamic>> lines, String anchorName) async {
    if (_addingLine || !_currentSession) return null;
    setState(() => _addingLine = true);
    final provider = source;
    final room = Map<String, dynamic>.from(_importRoom);
    try {
      final target = await _chooseDestination();
      if (target == null || !mounted || !_currentSession || source != provider)
        return null;
      final payload = [
        for (final line in lines)
          {
            ...line,
            'source_line_id': line['id'] ?? line['label'],
            'source_label': line['label'],
            'label':
                '${_sourceLabel(provider)} • $anchorName • ${line['label'] ?? 'Stream'}',
          }
      ];
      final result = await _importer.save(
          matchId: target, source: provider, room: room, lines: payload);
      if (!mounted || !_currentSession) return result;
      targetMatchId = target;
      AdminWebSourceCache.rememberMatch(target);
      // Health/video checks stay explicit in the quality sheet. A batch ADD
      // must not fan out a probe per selected line on Vercel/Edge Functions.
      widget.onMutated?.call();
      message('Added ${lines.length} line(s). Video playback is not verified.');
      return result;
    } finally {
      if (mounted)
        setState(() => _addingLine = false);
      else
        _addingLine = false;
    }
  }

  Future<bool> _addLine({
    required Map<String, dynamic> line,
    required String anchorName,
  }) async {
    try {
      return await _addLines([line], anchorName) != null;
    } catch (_) {
      message('Save was not confirmed. Your selection is kept.');
      return false;
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
    return match['combat_event_name']?.toString() ??
        '$home vs ${match['away_team'] ?? ''}';
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
      case 'arena':
        return 'Arena Koora';
      default:
        return _experimentalSourceNames[value] ?? 'Soco';
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
          controller: _sourceScroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            if (source == 'crichd') ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'football', label: Text('Football')),
                  ButtonSegment(value: 'combat', label: Text('Combat Sports'))
                ],
                selected: {_crichdSport},
                onSelectionChanged: (values) {
                  setState(() {
                    _crichdSport = values.single;
                    sourceMatches = const [];
                    dayFilter = 'all';
                  });
                  unawaited(_loadSoco());
                },
              ),
              if (_crichdCombat)
                DropdownButton<String>(
                  value: _combatCategory,
                  isExpanded: true,
                  items: [
                    for (final item in const {
                      'all': 'All combat sports',
                      'ufc': 'UFC',
                      'mma': 'MMA',
                      'boxing': 'Boxing',
                      'one': 'ONE Championship'
                    }.entries)
                      DropdownMenuItem(value: item.key, child: Text(item.value))
                  ],
                  onChanged: (value) {
                    setState(() {
                      _combatCategory = value ?? 'all';
                      sourceMatches = const [];
                    });
                    unawaited(_loadSoco());
                  },
                ),
              const SizedBox(height: 12),
            ],
            if (_isManualSource) _manualSourceCard(colors),
            if (!_isManualSource) ...[
              TextField(
                key: const Key('source-match-search'),
                controller: _sourceSearch,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => setState(() => _sourceQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search teams or leagues',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: const Icon(Icons.search, size: 19),
                  suffixIcon: _sourceQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _sourceSearch.clear();
                            _sourceQuery = '';
                          }),
                        ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                  visible.length == sourceMatches.length
                      ? '${sourceMatches.length} matches'
                      : '${visible.length} of ${sourceMatches.length} matches',
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
            ],
            if (!_isManualSource && source != 'yyzb' && source != 'arena')
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
            if (!_isManualSource && source != 'fawa' && source != 'cola')
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
                    _sourceQuery.trim().isEmpty
                        ? (_isExperimentalSource
                            ? (_experimentalEmptyReason ??
                                'No recognized football match data was returned by the website.')
                            : 'No football matches in this source section.')
                        : 'No matches found. Clear search to see all fixtures.',
                  ),
                ),
              ),
            ...visible.map((match) {
              final parsedKickoff = DateTime.tryParse(
                match['match_time']?.toString() ?? '',
              );
              final kickoff =
                  parsedKickoff == null ? null : myanmarTime(parsedKickoff);
              final displayKickoff = kickoff;
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
                      if (displayKickoff != null || !_isExperimentalSource) ...[
                        const SizedBox(height: 4),
                        Text(
                          match['kind'] == 'channel'
                              ? 'Broadcast channel'
                              : displayKickoff == null
                                  ? (match['time_label']
                                              ?.toString()
                                              .trim()
                                              .isNotEmpty ==
                                          true
                                      ? match['time_label'].toString()
                                      : 'Unknown time')
                                  : '${DateFormat('dd MMM • h:mm a', 'en_US').format(displayKickoff)}'
                                      ' MMT'
                                      '${match['kickoff_estimated'] == true ? ' • ESTIMATED' : ''}',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                      if (_isExperimentalSource && displayKickoff == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                              'Source page only • schedule not verified',
                              style: TextStyle(fontSize: 11)),
                        ),
                      const SizedBox(height: 12),
                      if (_extractingAnchorKey != null)
                        TextButton.icon(
                            onPressed: () {
                              ++_extractionGeneration;
                              setState(() => _extractingAnchorKey = null);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel link search')),
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
                            final name =
                                (anchor['nick_name'] ?? 'Streamer').toString();
                            final key = _anchorKey(match, anchor);
                            final status = _anchorStatuses[key] ?? 'unknown';
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
                              'detected' => ' • DETECTED ($lineCount)',
                              'offline' => ' • OFFLINE',
                              'checking' => ' • CHECKING (TAP)',
                              _ => ' • UNKNOWN',
                            };
                            final color = switch (status) {
                              'live' => Colors.redAccent,
                              'ready' => Colors.green,
                              'detected' => Colors.orange,
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
                                extracting ? '$name • LOADING' : '$name$suffix',
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
