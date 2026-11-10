import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../football_english.dart';
import '../services/tv_schedule_service.dart';
import '../widgets/football_match_guide_card.dart';

/// Compact match schedule for the Admin's own fixture list.
///
/// It is intentionally read-only: channel guide data is useful for seeing
/// live/next match times, but adding a stream line does not belong in a TV
/// schedule view.
class TvSchedulesPage extends StatefulWidget {
  const TvSchedulesPage({super.key, this.embedded = false, this.active = true});

  final bool embedded;
  final bool active;

  @override
  State<TvSchedulesPage> createState() => _TvSchedulesPageState();
}

class _TvSchedulesPageState extends State<TvSchedulesPage> {
  late Future<_ScheduleData> _schedule = _load();
  _ScheduleData? _lastSchedule;
  DateTime? _lastSuccessfulAt;
  late Future<_GuideResult> _guide = _loadGuide();
  String _view = 'upcoming';
  DateTime _lastRefreshAt = DateTime.now();

  void _refresh() => setState(() {
        _lastRefreshAt = DateTime.now();
        _schedule = _load();
        _guide = _loadGuide(refresh: true);
      });

  @override
  void didUpdateWidget(covariant TvSchedulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active &&
        DateTime.now().difference(_lastRefreshAt) >= const Duration(minutes: 2)) {
      _refresh(); // FutureBuilder holds last good rows while fetching.
    }
  }

  // Matches are essential; optional EPG must never block showing fixtures.
  Future<_ScheduleData> _load() async {
    final result = _ScheduleData(matches: await _loadMatches());
    _lastSchedule = result; // Keep last success on temporary network loss.
    _lastSuccessfulAt = DateTime.now();
    return result; // Including authoritative empty/deleted lists.
  }

  Future<_GuideResult> _loadGuide({bool refresh = false}) async {
    try {
      return _GuideResult(
          guide: await TvScheduleService().load(refresh: refresh));
    } catch (_) {
      return const _GuideResult(error: 'TV guide is temporarily unavailable.');
    }
  }

  Future<List<Map<String, dynamic>>> _loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,league,home_team,away_team,kickoff_at,sort_order,is_live,'
          'is_active,is_featured,publish_state,deleted_at',
        )
        .timeout(const Duration(seconds: 10));
    final rows = List<Map<String, dynamic>>.from(data)
        .where((row) => row['deleted_at'] == null)
        .toList();
    rows.sort(_compareMatches);
    return rows;
  }

  int _compareMatches(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aTime = DateTime.tryParse(a['kickoff_at']?.toString() ?? '');
    final bTime = DateTime.tryParse(b['kickoff_at']?.toString() ?? '');
    final byTime = (aTime ?? DateTime(9999)).compareTo(
      bTime ?? DateTime(9999),
    );
    if (byTime != 0) return byTime;
    final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
    final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
    return aOrder.compareTo(bOrder);
  }

  List<Map<String, dynamic>> _visibleMatches(
    List<Map<String, dynamic>> matches,
  ) {
    final now = DateTime.now().toUtc();
    return matches.where((match) {
      final label = '${match['league']} ${match['home_team']} ${match['away_team']}';
      // Schedule is football-only, never replay/highlight or other sports.
      if (RegExp(r'\b(replay|highlight|recap|cricket|tennis|basketball|formula 1|motorsport|rugby)\b',
          caseSensitive: false).hasMatch(label)) return false;
      if (match['is_active'] == false ||
          (match['publish_state'] ?? 'published') != 'published') {
        return false;
      }
      if (_view == 'live') return match['is_live'] == true;
      final kickoff = DateTime.tryParse(match['kickoff_at']?.toString() ?? '');
      return match['is_live'] == true ||
          (kickoff != null && !kickoff.toUtc().isBefore(now));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final page = FutureBuilder<_ScheduleData>(
      future: _schedule,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _lastSchedule;
        if (data == null && snapshot.hasError) {
          return _RetryState(
            message: 'Could not load matches. Check the connection and retry.',
            onRetry: _refresh,
          );
        }
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // Keep the last success while revalidating; never replay deleted
        // fixtures after a successful (possibly empty) response.
        final matches = _visibleMatches(data.matches);
        return FutureBuilder<_GuideResult>(
          future: _guide,
          builder: (context, guideSnapshot) {
            final guide = guideSnapshot.data;
            return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              if (widget.embedded)
                _ScheduleHeader(
                  guideError: guide?.error,
                  onRefresh: _refresh,
                ),
              if (widget.embedded) const SizedBox(height: 10),
              if (kIsWeb && snapshot.hasError && _lastSchedule != null) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_rounded),
                    title: const Text('Match refresh failed — showing saved schedule'),
                    subtitle: Text(_lastSuccessfulAt == null
                        ? 'Last successful update unavailable'
                        : 'Last successful: ${DateFormat('dd MMM HH:mm').format(_lastSuccessfulAt!.toLocal())}'),
                    trailing: TextButton(
                      onPressed: _refresh,
                      child: const Text('RETRY'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Live & upcoming'),
                    selected: _view == 'upcoming',
                    onSelected: (_) => setState(() => _view = 'upcoming'),
                  ),
                  ChoiceChip(
                    label: const Text('Live now'),
                    selected: _view == 'live',
                    onSelected: (_) => setState(() => _view = 'live'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${matches.length} MATCH${matches.length == 1 ? '' : 'ES'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              const SizedBox(height: 7),
              if (matches.isEmpty)
                const _EmptySchedule()
              else
                ...matches.map(
                  (match) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MatchScheduleCard(
                      match: match,
                      guide: guide?.guide,
                    ),
                  ),
                ),
            ],
          ),
        );
          },
        );
      },
    );

    if (widget.embedded) {
      // Both guide tabs use a dark guide canvas even when the Admin app is
      // in light mode. Scope text, icons and dropdown colors to that canvas
      // so black-on-black labels never disappear.
      return Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: FootballGuideColors.mint,
            brightness: Brightness.dark,
            surface: FootballGuideColors.background,
          ),
        ),
        child: ColoredBox(
          color: FootballGuideColors.background,
          child: page,
        ),
      );
    }
    return Scaffold(
      backgroundColor: FootballGuideColors.background,
      appBar: AppBar(
        title: const Text('TV Schedule'),
        actions: [
          IconButton(
            tooltip: 'Refresh TV schedule',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: page,
    );
  }
}

class _ScheduleData {
  const _ScheduleData({required this.matches});

  final List<Map<String, dynamic>> matches;
}

class _GuideResult {
  const _GuideResult({this.guide, this.error});

  final TvScheduleGuide? guide;
  final String? error;
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.guideError,
    required this.onRefresh,
  });

  final String? guideError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TV Schedule',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                guideError ?? 'Live and next match times only • MMT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      guideError == null ? colors.onSurfaceVariant : colors.error,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh TV schedule',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _MatchScheduleCard extends StatelessWidget {
  const _MatchScheduleCard({required this.match, required this.guide});
  final Map<String, dynamic> match;
  final TvScheduleGuide? guide;

  @override
  Widget build(BuildContext context) {
    final home = englishKnownFootballName(
      match['home_team']?.toString() ?? 'Home',
    );
    final away = englishKnownFootballName(
      match['away_team']?.toString() ?? 'Away',
    );
    final league = englishKnownFootballName(
      match['league']?.toString() ?? 'Football', kind: 'league',
    );
    final normalizedMatch = {
      ...match, 'home_team': home, 'away_team': away,
    };
    final airings = guide?.airingsForMatch(normalizedMatch) ??
        const <TvScheduleAiring>[];
    final possibleAirings = guide?.possibleAiringsForMatch(normalizedMatch) ??
        const <TvScheduleAiring>[];
    return FootballMatchGuideCard(
      league: league,
      match: '$home vs $away',
      kickoff: DateTime.tryParse(match['kickoff_at']?.toString() ?? ''),
      live: match['is_live'] == true,
      airings: [
        for (final airing in airings)
          FootballGuideAiring(
            channel: airing.channel, when: airing.when, region: airing.region,
            title: airing.title,
          ),
      ],
      possibleAirings: [
        for (final airing in possibleAirings)
          FootballGuideAiring(
            channel: airing.channel, when: airing.when, region: airing.region,
            title: airing.title,
          ),
      ],
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No live or upcoming matches in this view.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 36),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}


