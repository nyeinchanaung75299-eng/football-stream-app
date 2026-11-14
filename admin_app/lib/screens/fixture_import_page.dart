import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_links_page.dart';
import 'soco_import_page.dart';
import '../analytics_service.dart';
import '../football_english.dart';
import '../big_match_source_policy.dart';
import '../services/fixture_badge_enrichment.dart';
import '../widgets/resilient_logo.dart';
import '../services/function_gateway.dart';
import '../services/connected_channel_source.dart';
import '../widgets/repository_match_import_sheet.dart';

class FixtureImportPage extends StatefulWidget {
  const FixtureImportPage({super.key, this.onPublished, this.initialSource = 'cola', this.initialRepositoryEntryId});
  /// Called only after confirmed fixture IDs were written.
  final VoidCallback? onPublished;
  final String initialSource;
  final String? initialRepositoryEntryId;

  @override
  State<FixtureImportPage> createState() => _FixtureImportPageState();
}

class _FixtureImportPageState extends State<FixtureImportPage> {
  static const _pagesColaMirror =
      'https://nyeinchanaung75299-eng.github.io/football-stream-app/sources/cola.json';
  static const _rawColaMirror =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/sources/cola.json';

  static final bool _enableNoVpnFallback =
      const String.fromEnvironment(
        'ENABLE_NO_VPN_FALLBACK',
        defaultValue: '0',
      ).trim() ==
      '1';
  DateTime selectedDate = DateTime.now().toUtc()
      .add(const Duration(hours: 6, minutes: 30));
  String mode = 'date';
  static const _fixtureProviders = pickBigMatchProviders;
  late String fixtureSource = isPickBigMatchProvider(widget.initialSource)
      ? widget.initialSource : 'cola';
  final ConnectedChannelSource _repository = ConnectedChannelSource(source: 'repository');

  // Myanmar Standard Time is UTC+06:30 regardless of device time zone.
  // Unknown or timezone-ambiguous kickoffs are never replaced by now.
  DateTime? _myanmarKickoff(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (!RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
        .hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc().add(const Duration(hours: 6, minutes: 30));
  }
  bool loading = false;
  bool importing = false;
  String? errorText;
  String? _sourceFixtureDiagnostic;
  bool _offerAllDates = false;

  String? _diagnoseFixturePayload(dynamic payload, String provider) {
    if (payload is! Map || payload['diagnostics'] is! Map) return null;
    final diagnostics = payload['diagnostics'] as Map;
    final count = (diagnostics['candidate_count'] as num?)?.toInt() ?? 0;
    final timed = (diagnostics['confirmed_kickoff_count'] as num?)?.toInt() ?? 0;
    final estimate = (diagnostics['estimated_countdown_count'] as num?)?.toInt() ?? 0;
    if (count > 0) {
      final available = diagnostics['available_days_mmt'];
      final days = available is List
          ? available.map((day) => day.toString()).take(6).join(', ')
          : '';
      return '${_providerLabel(provider)} returned $count football events '
          '($timed confirmed, $estimate countdown estimated). '
          '${days.isEmpty ? "No verified Myanmar dates are available." : "Available MMT dates: $days."} '
          'Choose All to inspect every dated fixture.';
    }
    final status = diagnostics['content_state']?.toString();
    if (status == 'browser_render_or_unsupported_markup') {
      return '${_providerLabel(provider)} did not publish readable football '
          'matches in HTML or embedded JSON. It may require browser JavaScript '
          'or a permitted public API.';
    }
    if (status == 'no_recognized_football_fixtures') {
      return '${_providerLabel(provider)} contained JSON scripts, but no '
          'trusted football event was recognized. Script data may be '
          'configuration or browser-only fixtures.';
    }
    return '${_providerLabel(provider)} returned no recognized football fixtures.';
  }

  List<Map<String, dynamic>> fixtures = [];
  final Set<int> selectedIds = {};
  final Map<String, List<dynamic>> _trustedBadgeFixturesCache = {};
  List<dynamic>? _trustedColaBadgesCache;
  DateTime? _trustedColaBadgesCheckedAt;
  int _loadEpoch = 0;

  @override
  void initState() {
    super.initState();
    if (fixtureSource == 'repository') {
      mode = 'all';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadFixtures();
      });
    }
  }

  @override
  void dispose() {
    _loadEpoch += 1;
    super.dispose();
  }

  Future<void> pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime.now().toUtc()
          .add(const Duration(hours: 6, minutes: 30))
          .subtract(const Duration(days: 30)),
      lastDate: DateTime.now().toUtc()
          .add(const Duration(hours: 6, minutes: 30))
          .add(const Duration(days: 365)),
      initialDate: selectedDate,
    );

    if (result == null) return;

    setState(() {
      selectedDate = result;
      mode = 'date';
    });

    await loadFixtures();
  }

  int _stableSourceFixtureId(String value) {
    // Stable 32-bit FNV-1a, moved into a separate bigint range so ColaTV
    // fixture ids cannot collide with normal football API fixture ids.
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 8000000000 + hash;
  }

  Future<Map<String, dynamic>> _loadColaMirror() async {
    Object? lastError;
    Map<String, dynamic>? emptyFallback;
    for (final url in const [_pagesColaMirror, _rawColaMirror]) {
      try {
        final response = await http
            .get(
              Uri.parse(url).replace(
                queryParameters: {
                  't': DateTime.now().millisecondsSinceEpoch.toString(),
                },
              ),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'ColaTV mirror HTTP ' + response.statusCode.toString(),
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('ColaTV mirror response is invalid.');
        }
        final data = Map<String, dynamic>.from(decoded);
        final rows = data['matches'];
        if (rows is! List) {
          throw const FormatException('ColaTV mirror match list is invalid.');
        }
        if (rows.isNotEmpty) return data;
        emptyFallback ??= data;
      } catch (e) {
        lastError = e;
      }
    }
    if (emptyFallback != null) return emptyFallback;
    throw Exception(lastError ?? 'ColaTV mirror is unavailable.');
  }

  // Repository fixtures are metadata from the connected, admin-only catalog.
  // Do not manufacture start times or stream URLs. Existing native lines
  // continue through publish_repository_match, not publish_featured_matches.
  Future<List<Map<String, dynamic>>> _loadRepositoryFixtures(
      String requestedMode, DateTime requestedDate) async {
    final entries = <Map<String, dynamic>>[];
    // The server paginates 100 at a time. Bound to 5 requests/500 entries.
    for (var page = 0; page < 5; page++) {
      final payload = await _repository.request('catalog', {
        'kind': 'event', 'page': page,
      });
      final raw = payload['entries'];
      if (raw is! List) throw const FormatException('Repository catalog is invalid.');
      for (final item in raw) {
        if (item is Map) entries.add(Map<String, dynamic>.from(item));
      }
      final total = (payload['total'] as num?)?.toInt() ?? entries.length;
      if (raw.isEmpty || entries.length >= total) break;
    }

    final rows = <Map<String, dynamic>>[];
    final wanted = DateTime(requestedDate.year, requestedDate.month, requestedDate.day);
    var missingTime = 0;
    for (final item in entries) {
      final meta = item['event_meta'];
      if (meta is! Map) continue;
      final home = (meta['home_team'] ?? '').toString().trim();
      final away = (meta['away_team'] ?? '').toString().trim();
      final id = (item['id'] ?? '').toString();
      if (!id.startsWith('repo:match:') || home.isEmpty || away.isEmpty) continue;
      final utc = meta['kickoff_at']?.toString() ?? '';
      final mmt = _myanmarKickoff(utc);
      // A missing time requires explicit MMT time selection on import;
      // show these only in All, never claim they are live or on a given day.
      if (mmt == null) {
        missingTime++;
        if (requestedMode != 'all') continue;
      } else {
        if (requestedMode == 'live') continue; // catalog has no verified live status
        if (requestedMode == 'date' &&
            DateTime(mmt.year, mmt.month, mmt.day) != wanted) continue;
      }
      rows.add({
        'fixture_id': _stableSourceFixtureId('repository::$id'),
        'provider': 'repository',
        'repository_entry_id': id,
        'repository_entry': item,
        'league_name': (meta['league'] ?? 'Football').toString(),
        'home_name': home, 'away_name': away,
        'home_logo': meta['home_logo_url'], 'away_logo': meta['away_logo_url'],
        'kickoff_at': mmt == null ? null : utc,
        'status_short': mmt == null ? 'TIME PENDING' : 'NS',
        'is_live': false,
      });
    }
    rows.sort((a, b) =>
        (a['kickoff_at']?.toString() ?? '9999').compareTo(
            b['kickoff_at']?.toString() ?? '9999'));
    if (rows.isEmpty && missingTime > 0 && requestedMode != 'all') {
      _offerAllDates = true;
      _sourceFixtureDiagnostic =
          'Repository has $missingTime fixture(s) without a verified kickoff. '
          'Choose All to set an MMT kickoff when publishing.';
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadSourceFixtures(
      String provider, String requestedMode, DateTime requestedDate) async {
    // Provider restriction is enforced at the network entrypoint as well as
    // the dropdown. Stream Sources retain their own independent providers.
    if (!isPickBigMatchProvider(provider)) {
      throw ArgumentError.value(provider, 'provider',
          'Provider is not enabled for Pick Big Matches.');
    }
    if (provider == 'repository') {
      return _loadRepositoryFixtures(requestedMode, requestedDate);
    }
    dynamic data;
    if (!_enableNoVpnFallback) {
      data = await FunctionGateway.invoke(
        'source-match-list',
        body: {'source': provider, 'date': DateFormat('yyyy-MM-dd').format(requestedDate)},
      );
    } else {
      try {
        data = await FunctionGateway.invoke(
          'source-match-list',
          body: {'source': provider, 'date': DateFormat('yyyy-MM-dd').format(requestedDate)},
        );
      } catch (_) {
        if (provider != 'cola') rethrow;
        data = await _loadColaMirror();
      }
    }
    if (provider == fixtureSource && provider != 'cola') {
      _sourceFixtureDiagnostic = _diagnoseFixturePayload(data, provider);
    }
    final raw = data is Map ? data['matches'] : null;
    if (raw is! List) {
      throw FormatException('${_providerLabel(provider)} match list is invalid.');
    }

    final wantedDate = DateTime(
      requestedDate.year,
      requestedDate.month,
      requestedDate.day,
    );

    final rows = <Map<String, dynamic>>[];
    final publishedMmtDays = <String>{};
    var datedFixtureCount = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final matchTime = _myanmarKickoff(row['match_time']);
      if (matchTime == null) continue;
      datedFixtureCount++;
      publishedMmtDays.add(DateFormat('yyyy-MM-dd').format(matchTime));

      final isLive = row['hot'] == true ||
          row['status']?.toString().toUpperCase() == 'LIVE' ||
          row['match_status']?.toString().toUpperCase() == 'LIVE';

      if (requestedMode == 'live') {
        if (!isLive) continue;
      } else if (requestedMode == 'date') {
        final day = DateTime(matchTime.year, matchTime.month, matchTime.day);
        if (day != wantedDate) continue;
      }
      // mode == 'all' intentionally keeps every ColaTV football match,
      // regardless of kickoff date or live status.

      final home = (row['home_team'] ?? '').toString().trim();
      final away = (row['away_team'] ?? '').toString().trim();
      if (home.isEmpty || away.isEmpty) continue;

      final sourceKey = (row['source_id'] ??
              row['page_url'] ??
              '${home.toLowerCase()}::${away.toLowerCase()}::${row['match_time'] ?? ''}')
          .toString();

      rows.add({
        'fixture_id': row['fixture_id'] is num
            ? (row['fixture_id'] as num).toInt()
            : _stableSourceFixtureId('$provider::$sourceKey'),
        'provider': provider,
        'league_name': (row['league'] ?? row['league_name'] ?? 'Football').toString(),
        'home_name': home,
        'away_name': away,
        'home_logo': row['home_logo'],
        'away_logo': row['away_logo'],
        'kickoff_at': row['match_time'].toString(),
        'status_short': isLive ? 'LIVE' : 'NS',
        'is_live': isLive,
        'source_page_url': row['page_url'],
        'poster_url': row['poster_url'],
        'kickoff_estimated': row['kickoff_estimated'] == true,
        'kickoff_source': row['kickoff_source'],
      });
    }

    // A source can have perfectly valid kickoff times on OTHER MMT dates.
    // Date/Live filters returning zero must never claim the source has zero
    // valid kickoff timestamps or confuse an upstream parsing failure.
    if (rows.isEmpty && provider == fixtureSource && provider != 'cola' &&
        datedFixtureCount > 0) {
      _offerAllDates = requestedMode != 'all';
      final days = publishedMmtDays.toList()..sort();
      final preview = days.take(7).join(', ');
      final date = DateFormat('yyyy-MM-dd').format(requestedDate);
      if (requestedMode == 'date') {
        _sourceFixtureDiagnostic = '${_providerLabel(provider)} returned '
            '$datedFixtureCount dated football fixtures, but none on $date MMT. '
            'Available MMT dates: $preview. Choose All or another date.';
      } else if (requestedMode == 'live') {
        _sourceFixtureDiagnostic = '${_providerLabel(provider)} returned '
            '$datedFixtureCount dated fixtures, but none are marked LIVE. '
            'Choose All for upcoming games.';
      }
    }

    rows.sort((a, b) {
      final at = DateTime.tryParse(a['kickoff_at']?.toString() ?? '') ??
          DateTime(9999);
      final bt = DateTime.tryParse(b['kickoff_at']?.toString() ?? '') ??
          DateTime(9999);
      return at.compareTo(bt);
    });

    // CricHD and Score088TV sometimes omit badges even when ColaTV publishes
    // the SAME football fixture with genuine source badges. Read Cola's
    // *existing* endpoint; do not modify its parsing or replace its images.
    // Never guess from team names alone: the merger also requires a kickoff
    // within two hours and the correct home/away pair.
    if ((provider == 'crichd' || provider == 'score088') &&
        rows.isNotEmpty &&
        rows.any((row) => verifiedBadgeUrl(row['home_logo']) == null ||
            verifiedBadgeUrl(row['away_logo']) == null)) {
      Future<List<dynamic>> colaBadges() async {
        final checked = _trustedColaBadgesCheckedAt;
        if (checked != null &&
            DateTime.now().difference(checked) < const Duration(minutes: 2)) {
          return _trustedColaBadgesCache ?? <dynamic>[];
        }
        try {
          final data = await FunctionGateway.invoke(
            'source-match-list',
            body: {'source': 'cola'},
          ).timeout(const Duration(seconds: 7));
          final raw = data is Map ? data['matches'] : null;
          if (raw is! List) return <dynamic>[];
          final trusted = <dynamic>[];
          for (final item in raw) {
            if (item is! Map) continue;
            trusted.add({
              'home_name': item['home_team'],
              'away_name': item['away_team'],
              'kickoff_at': item['match_time'],
              'home_logo': item['home_logo'],
              'away_logo': item['away_logo'],
            });
          }
          _trustedColaBadgesCache = trusted;
          _trustedColaBadgesCheckedAt = DateTime.now();
          return trusted;
        } catch (_) {
          return <dynamic>[];
        }
      }

      Future<List<dynamic>> footballBadges(String fixtureDate) async {
        final cached = _trustedBadgeFixturesCache[fixtureDate];
        if (cached != null) return cached;
        try {
          final data = await FunctionGateway.invoke(
            'football-fixtures',
            body: {'mode': 'date', 'date': fixtureDate},
          ).timeout(const Duration(seconds: 7));
          final trusted = data is Map ? data['fixtures'] : null;
          if (trusted is! List) return <dynamic>[];
          _trustedBadgeFixturesCache[fixtureDate] = trusted;
          return trusted;
        } catch (_) {
          return <dynamic>[];
        }
      }

      // "All" can include multiple kickoff days. Avoid looking only at the
      // first row; cap the number of lookups and run independent reads together.
      final dates = missingBadgeUtcDates(rows);
      final lookups = await Future.wait<List<dynamic>>([
        colaBadges(),
        ...dates.map(footballBadges),
      ]);
      final verified = <dynamic>[
        for (final lookup in lookups) ...lookup,
      ];
      return mergeVerifiedFootballBadges(rows, verified);
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadFallbackFixtures(
      String requestedMode, DateTime requestedDate) async {
    final data = await FunctionGateway.invoke(
      'football-fixtures',
      body: {
        'mode': requestedMode,
        'date': DateFormat('yyyy-MM-dd').format(requestedDate),
      },
    );
    if (data is! Map) {
      throw Exception('Unexpected API response.');
    }
    if (data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    final rows = data['fixtures'];
    if (rows is! List) {
      throw Exception('No fixture list returned.');
    }
    return rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> loadFixtures() async {
    if (importing) return;
    final requestedMode = mode;
    final requestedDate = selectedDate;
    final epoch = ++_loadEpoch;
    bool current() => mounted && epoch == _loadEpoch;
    setState(() {
      loading = true;
      errorText = null;
      _sourceFixtureDiagnostic = null;
      _offerAllDates = false;
      selectedIds.clear();
    });

    String provider = fixtureSource;
    try {
      List<Map<String, dynamic>> rows = const [];

      try {
        rows = await _loadSourceFixtures(provider, requestedMode, requestedDate);
      } catch (_) {
        if (provider != 'cola') rethrow;
        rows = const [];
      }

      if (rows.isEmpty && provider == 'cola') {
        provider = 'fallback';
        rows = await _loadFallbackFixtures(requestedMode, requestedDate);
      }

      unawaited(AnalyticsService.capture(
        'fixture list loaded',
        properties: {
          'mode': requestedMode,
          'fixture_count': rows.length,
          'primary_source': fixtureSource,
          'served_by': provider,
        },
      ));

      // Cola/football API requires confirmed kickoff. Repository supports
      // untimed events in All mode, but asks the Admin for an explicit MMT time.
      final timedRows = rows.where((row) =>
          fixtureSource == 'repository' ||
          _myanmarKickoff(row['kickoff_at']) != null).toList();
      if (!current()) return;
      setState(() {
        fixtures = timedRows;
        if (fixtureSource == 'repository' && widget.initialRepositoryEntryId != null) {
          for (final row in timedRows) {
            if (row['repository_entry_id'] == widget.initialRepositoryEntryId) {
              selectedIds.add(row['fixture_id'] as int);
            }
          }
        }
        if (timedRows.isEmpty) {
          errorText = _sourceFixtureDiagnostic ??
              'No matches with confirmed or fresh countdown-based Myanmar kickoff times '
              'were returned by ${_providerLabel(fixtureSource)}.';
        }
      });
    } catch (e) {
      unawaited(AnalyticsService.capture(
        'fixture list failed',
        properties: {
          'mode': requestedMode,
          'primary_source': fixtureSource,
        },
      ));
      if (!current()) return;
      setState(() {
        fixtures = [];
        final raw = e.toString();
        final lower = raw.toLowerCase();
        if (fixtureSource != 'cola') {
          errorText = '${_providerLabel(fixtureSource)} match data failed: '
              '${raw.replaceFirst('Exception: ', '')}';
        } else if (lower.contains('football_providers_missing') ||
            lower.contains('no football fixture provider is configured')) {
          errorText =
              'ColaTV had no usable matches and no fallback fixture API is configured.';
        } else if (lower.contains('account is suspended') &&
            !lower.contains('football_data_org')) {
          errorText =
              'ColaTV had no usable matches and API-Football is suspended. Configure the backup fixture provider.';
        } else {
          errorText =
              'ColaTV and fallback fixtures could not be loaded: ${raw.replaceFirst('Exception: ', '')}';
        }
      });
    } finally {
      if (current()) setState(() => loading = false);
    }
  }

  void toggleFixture(int id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  Future<void> _publishRepositorySelection(
      List<Map<String, dynamic>> chosen) async {
    var published = 0;
    var restored = 0;
    final errors = <String>[];
    final ids = <String>[];
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    for (final row in chosen) {
      if (!mounted || client.auth.currentUser?.id != userId) return;
      final entryId = row['repository_entry_id']?.toString() ?? '';
      final title = '${row['home_name']} vs ${row['away_name']}';
      if (entryId.isEmpty) continue;
      DateTime? kickoff = DateTime.tryParse(
        row['kickoff_at']?.toString() ?? '',
      )?.toUtc();
      if (kickoff == null) {
        final raw = row['repository_entry'];
        if (raw is! Map) continue;
        kickoff = await showModalBottomSheet<DateTime>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => RepositoryMatchImportSheet(
            entry: Map<String, dynamic>.from(raw),
          ),
        );
        if (!mounted || client.auth.currentUser?.id != userId) return;
        if (kickoff == null) {
          errors.add('$title: kickoff was not selected');
          continue;
        }
      }
      try {
        final response = await client.rpc('publish_repository_match', params: {
          'p_entry_id': entryId,
          'p_kickoff_at': kickoff.toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 20));
        if (!mounted || client.auth.currentUser?.id != userId) return;
        final result = response is Map ? resultMap(response) : <String, dynamic>{};
        if (result['ok'] == true) {
          published++;
          final id = result['match_id']?.toString() ?? '';
          if (id.isNotEmpty) ids.add(id);
          if (result['restored'] == true) restored++;
        } else {
          final reason = switch (result['code']) {
            'previously_finished' => 'existing match already finished',
            'no_importable_lines' => 'no usable native stream lines',
            'ambiguous_match' => 'more than one existing match matched',
            'source_missing' => 'repository entry is no longer available',
            'metadata_pending' => 'missing team names',
            'kickoff_required' => 'kickoff confirmation required',
            _ => 'not published',
          };
          errors.add('$title: $reason');
        }
      } catch (_) {
        errors.add('$title: request failed; check Controls before retrying');
      }
    }
    if (!mounted || client.auth.currentUser?.id != userId) return;
    if (published > 0) widget.onPublished?.call();
    setState(() => selectedIds.clear());
    final details = <String>[
      '$published Repository match(es) processed.',
      if (restored > 0)
        '$restored previously deleted match(es) restored and re-published.',
      for (final issue in errors.take(3)) issue,
    ].join(' ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(details), duration: const Duration(seconds: 7)),
    );
    if (published == 1 && ids.isNotEmpty && errors.isEmpty) {
      await Navigator.of(context).push<void>(MaterialPageRoute(
        settings: const RouteSettings(name: '/admin/stream-servers'),
        builder: (_) => LiveLinksPage(initialMatchId: ids.first),
      ));
    }
  }

  Map<String, dynamic> resultMap(Map response) =>
      Map<String, dynamic>.from(response);

  Future<void> importSelected() async {
    if (importing || loading) return;
    final chosen = fixtures
        .where((f) => selectedIds.contains(f['fixture_id'] as int))
        .toList();

    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one match.')),
      );
      return;
    }

    setState(() => importing = true);

    try {
      if (fixtureSource == 'repository') {
        await _publishRepositorySelection(chosen);
        return;
      }
      final payload = chosen
          .map(
            (f) => <String, dynamic>{
              'fixture_id': f['fixture_id'],
              'provider': (f['provider'] ?? 'api_football').toString(),
              'league_name': f['league_name'],
              'home_name': f['home_name'],
              'away_name': f['away_name'],
              'home_logo': f['home_logo'],
              'away_logo': f['away_logo'],
              'kickoff_at': f['kickoff_at'],
              'status_short': f['status_short'] ?? 'NS',
              'is_live': f['is_live'] == true,
            },
          )
          .toList();

      // One RPC appends the selected matches to the featured set. Existing
      // unfinished/current featured matches stay published instead of being
      // replaced when a new Big Match is added.
      final result = await Supabase.instance.client.rpc(
        'publish_featured_matches',
        params: {'p_fixtures': payload},
      ).timeout(const Duration(seconds: 15));

      final resultMap = result is Map
          ? Map<String, dynamic>.from(result)
          : const <String, dynamic>{};
      final savedIds = (resultMap['saved_ids'] as List? ?? const [])
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList();
      final skippedDeleted =
          (resultMap['skipped_deleted'] as num?)?.toInt() ?? 0;
      final restoredCount =
          (resultMap['restored_count'] as num?)?.toInt() ?? 0;
      // A successful no-op (all fixtures skipped) must not invalidate a
      // retained guide on either Web or Android.
      if (savedIds.isNotEmpty && mounted) {
        widget.onPublished?.call();
      }

      unawaited(AnalyticsService.capture(
        'matches published',
        properties: {
          'requested_count': chosen.length,
          'published_count':
              (resultMap['published_count'] as num?)?.toInt() ?? savedIds.length,
          'skipped_deleted': skippedDeleted,
          'restored_count': restoredCount,
        },
      ));

      if (!mounted) return;

      setState(() => selectedIds.clear());

      if (restoredCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$restoredCount deleted match(es) restored and re-published.'),
        ));
      }
      if (skippedDeleted > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$skippedDeleted deleted match(es) were skipped and not restored.',
            ),
          ),
        );
      }

      if (chosen.length == 1 && savedIds.isNotEmpty) {
        final streamAction = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 44),
                const SizedBox(height: 10),
                const Text(
                  'Match published',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pick an available stream source now, or add an authorized stream manually.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'source'),
                    icon: const Icon(Icons.podcasts_rounded),
                    label: const Text('PICK STREAM SOURCE'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'manual'),
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('ADD STREAM MANUALLY'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, 'done'),
                  child: const Text('DONE'),
                ),
              ],
            ),
          ),
        );

        if (streamAction == 'source' && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(
                name: '/admin/stream-source-picker',
              ),
              builder: (_) => SocoImportPage(
                initialMatchId: savedIds.first,
                initialSource: fixtureSource,
              ),
            ),
          );
        } else if (streamAction == 'manual' && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(
                name: '/admin/stream-servers',
              ),
              builder: (_) => LiveLinksPage(
                initialMatchId: savedIds.first,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${chosen.length} matches published. Open Stream Sources or Stream Servers to add lines.',
            ),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final deleted = e.message.contains('All selected matches were previously deleted');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(deleted
            ? 'These matches were deleted in Controls. Nothing was republished. '
              'Choose a different match or restore explicitly in Controls.'
            : 'Publish failed: ${e.message}'),
        duration: const Duration(seconds: 6),
      ));
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not confirm publishing. Check Matches before trying again.')));
      }
    } catch (e) {
      unawaited(AnalyticsService.capture(
        'match publish failed',
        properties: {'requested_count': chosen.length},
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  String _providerLabel(dynamic value) {
    final known = _fixtureProviders[value?.toString()];
    if (known != null) return known;
    switch (value?.toString()) {
      case 'cola':
        return 'ColaTV';
      case 'football_data_org':
        return 'football-data.org';
      case 'source_fallback':
      case 'soco':
      case 'yyzb':
        return 'Soco / YYZB fallback';
      default:
        return 'API-Football';
    }
  }

  Widget modeButton({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final active = mode == value;

    return Expanded(
      child: active
          ? FilledButton.icon(
              onPressed: importing
                  ? null
                  : () async {
                setState(() => mode = value);
                await loadFixtures();
              },
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: importing
                  ? null
                  : () async {
                setState(() => mode = value);
                await loadFixtures();
              },
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Big Matches'),
      ),
      bottomNavigationBar: selectedIds.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: importing ? null : importSelected,
                  icon: importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_task_rounded),
                  label: Text(
                    importing
                        ? 'ADDING...'
                        : 'PUBLISH SELECTED (${selectedIds.length})',
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          DropdownButtonFormField<String>(
            value: fixtureSource,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Pick Big Match source',
              border: OutlineInputBorder(),
            ),
            items: _fixtureProviders.entries
                .map((entry) => DropdownMenuItem<String>(
                      value: entry.key, child: Text(entry.value),
                    ))
                .toList(),
            onChanged: importing ? null : (value) {
              if (value == null || value == fixtureSource) return;
              setState(() {
                fixtureSource = value;
                // Repository also contains fixtures without a kickoff;
                // these require manual confirmation and are shown in All.
                if (value == 'repository') mode = 'all';
              });
              loadFixtures();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              modeButton(
                value: 'date',
                label: 'Date',
                icon: Icons.calendar_month_rounded,
              ),
              const SizedBox(width: 8),
              modeButton(
                value: 'live',
                label: 'Live',
                icon: Icons.podcasts_rounded,
              ),
              const SizedBox(width: 8),
              modeButton(
                value: 'all',
                label: 'All',
                icon: Icons.view_list_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mode == 'date')
            OutlinedButton.icon(
              onPressed: importing ? null : pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text(
                DateFormat('EEE, dd MMM yyyy').format(selectedDate),
              ),
            ),
          const SizedBox(height: 10),
          if (fixtures.isEmpty && !loading)
            FilledButton.tonalIcon(
              onPressed: loadFixtures,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('LOAD MATCHES'),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (errorText != null && !loading)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 38),
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    if (_offerAllDates && mode != 'all')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.icon(
                          onPressed: () {
                            setState(() => mode = 'all');
                            loadFixtures();
                          },
                          icon: const Icon(Icons.view_list_rounded),
                          label: const Text('SHOW ALL DATES'),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: loadFixtures,
                      child: const Text('TRY AGAIN'),
                    ),
                  ],
                ),
              ),
            ),
          if (fixtures.isNotEmpty && !loading) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fixtures.length} fixtures',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (selectedIds.length == fixtures.length) {
                        selectedIds.clear();
                      } else {
                        selectedIds
                          ..clear()
                          ..addAll(
                            fixtures.map((e) => e['fixture_id'] as int),
                          );
                      }
                    });
                  },
                  child: Text(
                    selectedIds.length == fixtures.length
                        ? 'CLEAR'
                        : 'SELECT ALL',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...fixtures.map((f) {
              final id = f['fixture_id'] as int;
              final checked = selectedIds.contains(id);
              final kickoff = _myanmarKickoff(f['kickoff_at']);

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: checked
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: .5),
                      width: checked ? 1.5 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => toggleFixture(id),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        children: [
                          Checkbox(
                            value: checked,
                            onChanged: (_) => toggleFixture(id),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  englishKnownFootballName(f['league_name'].toString(), kind: 'league'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${englishKnownFootballName('${f['home_name']}')}  vs  ${englishKnownFootballName('${f['away_name']}')}',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  kickoff == null
                                    ? 'Kickoff time pending • select MMT time when publishing'
                                    : '${DateFormat('dd MMM • h:mm a', 'en_US').format(kickoff)}'
                                      ' MMT${f['kickoff_estimated'] == true ? ' • ESTIMATED' : ''}'
                                      '${f['status_short'] == null ? '' : ' • ${f['status_short']}'}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                if (f['kickoff_estimated'] == true)
                                  const Text(
                                    'Calculated from source countdown • verify before publishing',
                                    style: TextStyle(fontSize: 10.5),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              _TeamLogo(
                                url: f['home_logo']?.toString(),
                                fallbackUrl: f['home_logo_fallback']?.toString(),
                              ),
                              const SizedBox(height: 5),
                              _TeamLogo(
                                url: f['away_logo']?.toString(),
                                fallbackUrl: f['away_logo_fallback']?.toString(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({this.url, this.fallbackUrl});

  final String? url;
  final String? fallbackUrl;

  static const _unavailable = SizedBox(
    width: 28,
    height: 28,
    child: Icon(Icons.shield_outlined, size: 20),
  );

  @override
  Widget build(BuildContext context) {
    // Keep the original provider logo path (including ColaTV's existing
    // URLs) byte-for-byte. The trusted secondary image is HTTPS-validated.
    // Do not regress providers which already render badges correctly.
    final primary = url?.trim().isNotEmpty == true ? url!.trim() : null;
    final backup = verifiedBadgeUrl(fallbackUrl);
    if (primary == null && backup == null) return _unavailable;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ResilientLogo(
        value: primary ?? backup!, width: 28, height: 28,
        fallback: backup != null && backup != primary
          ? ResilientLogo(value: backup, width: 28, height: 28, fallback: _unavailable)
          : _unavailable,
      ),
    );
  }
}
