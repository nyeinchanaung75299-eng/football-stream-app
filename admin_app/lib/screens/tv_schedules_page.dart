import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../football_english.dart';
import '../services/tv_schedule_service.dart';

/// Compact match schedule for the Admin's own fixture list.
///
/// It is intentionally read-only: channel guide data is useful for seeing
/// live/next match times, but adding a stream line does not belong in a TV
/// schedule view.
class TvSchedulesPage extends StatefulWidget {
  const TvSchedulesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TvSchedulesPage> createState() => _TvSchedulesPageState();
}

class _TvSchedulesPageState extends State<TvSchedulesPage> {
  late Future<_ScheduleData> _schedule = _load();
  String _view = 'upcoming';

  void _refresh() => setState(() => _schedule = _load());

  Future<_ScheduleData> _load() async {
    final matchesFuture = _loadMatches();
    final guideFuture = _loadGuide();
    final matches = await matchesFuture;
    final guideResult = await guideFuture;
    return _ScheduleData(
      matches: matches,
      guide: guideResult.guide,
      guideError: guideResult.error,
    );
  }

  Future<_GuideResult> _loadGuide() async {
    try {
      return _GuideResult(guide: await TvScheduleService().load());
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
        if (snapshot.hasError) {
          return _RetryState(
            message: 'Could not load matches. Check the connection and retry.',
            onRetry: _refresh,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final matches = _visibleMatches(data.matches);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              if (widget.embedded)
                _ScheduleHeader(
                  guideError: data.guideError,
                  onRefresh: _refresh,
                ),
              if (widget.embedded) const SizedBox(height: 10),
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
                      guide: data.guide,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (widget.embedded) return page;
    return Scaffold(
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
  const _ScheduleData({
    required this.matches,
    this.guide,
    this.guideError,
  });

  final List<Map<String, dynamic>> matches;
  final TvScheduleGuide? guide;
  final String? guideError;
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
    final colors = Theme.of(context).colorScheme;
    final home = englishKnownFootballName(
      match['home_team']?.toString() ?? 'Home',
    );
    final away = englishKnownFootballName(
      match['away_team']?.toString() ?? 'Away',
    );
    final league = englishKnownFootballName(
      match['league']?.toString() ?? 'Football',
      kind: 'league',
    );
    final kickoff = DateTime.tryParse(match['kickoff_at']?.toString() ?? '');
    final isLive = match['is_live'] == true;
    final airings = guide?.airingsForMatch({
          ...match,
          'home_team': home,
          'away_team': away,
        }) ??
        const <TvScheduleAiring>[];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    league,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                _StatusPill(isLive: isLive),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$home vs $away',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  kickoff == null
                      ? 'Kickoff time unavailable'
                      : '${DateFormat('EEE, d MMM • h:mm a', 'en_US').format(_yangon(kickoff))} MMT',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (airings.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final airing in airings.take(3))
                    _AiringChip(airing: airing),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiringChip extends StatelessWidget {
  const _AiringChip({required this.airing});

  final TvScheduleAiring airing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = DateFormat('h:mm a', 'en_US').format(_yangon(airing.when));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${airing.channel} • $time',
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isLive ? colors.error : colors.primary).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isLive ? 'LIVE' : 'UPCOMING',
        style: TextStyle(
          color: isLive ? colors.error : colors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
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

DateTime _yangon(DateTime value) =>
    value.toUtc().add(const Duration(hours: 6, minutes: 30));
