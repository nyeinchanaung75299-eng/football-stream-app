import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../football_english.dart';
import '../services/tv_schedule_service.dart';
import 'match_channel_lines_page.dart';

/// Match-centred TV guide for the Admin's own channel catalog.
///
/// Source-browser providers deliberately never appear here. A line is shown
/// only when it came from My Channels, or an EPG programme has matched one of
/// those catalog channels.
class TvSchedulesPage extends StatefulWidget {
  const TvSchedulesPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TvSchedulesPage> createState() => _TvSchedulesPageState();
}

class _TvSchedulesPageState extends State<TvSchedulesPage> {
  late Future<_ScheduleData> _schedule = _load();
  String _view = 'all';

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
      // Match management remains available when the public guide is offline.
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
    final matchIds = rows.map((row) => row['id'].toString()).toList();
    if (matchIds.isEmpty) return rows;

    try {
      final links = await Supabase.instance.client
          .from('stream_links')
          .select(
            'match_id,label,channel_id,channel_line_id,is_active,sort_order',
          )
          .inFilter('match_id', matchIds)
          .order('sort_order')
          .timeout(const Duration(seconds: 10));
      final labelsByMatch = <String, List<String>>{};
      for (final raw in links) {
        final line = Map<String, dynamic>.from(raw);
        // Only explicit catalog associations are TV-channel lines. This keeps
        // Soco, YYZB, Fawa and ColaTV source-provider rows out of this page.
        if (line['channel_id'] == null || line['channel_line_id'] == null) {
          continue;
        }
        if (line['is_active'] == false) continue;
        final label = line['label']?.toString().trim() ?? '';
        if (label.isEmpty) continue;
        final target = labelsByMatch.putIfAbsent(
          line['match_id'].toString(),
          () => <String>[],
        );
        if (!target.contains(label)) target.add(label);
      }
      for (final match in rows) {
        match['_tv_lines'] =
            labelsByMatch[match['id'].toString()] ?? const <String>[];
      }
    } catch (_) {
      // The page is still useful during a short database migration rollout.
      for (final match in rows) {
        match['_tv_lines'] = const <String>[];
      }
    }
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
      if (_view == 'all') return true;
      if (_view == 'live') return match['is_live'] == true;
      final kickoff = DateTime.tryParse(match['kickoff_at']?.toString() ?? '');
      return match['is_live'] == true ||
          (kickoff != null && !kickoff.toUtc().isBefore(now));
    }).toList(growable: false);
  }

  Future<void> _manageLines(Map<String, dynamic> match) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => MatchChannelLinesPage(match: match)),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final page = FutureBuilder<_ScheduleData>(
      future: _schedule,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _RetryState(
            message: 'Could not load your matches. Check the connection and retry.',
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              _Header(
                guide: data.guide,
                guideError: data.guideError,
                onRefresh: _refresh,
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'all',
                    icon: Icon(Icons.list_alt_rounded),
                    label: Text('All'),
                  ),
                  ButtonSegment(
                    value: 'upcoming',
                    icon: Icon(Icons.upcoming_rounded),
                    label: Text('Upcoming'),
                  ),
                  ButtonSegment(
                    value: 'live',
                    icon: Icon(Icons.podcasts_rounded),
                    label: Text('Live'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (selected) {
                  setState(() => _view = selected.first);
                },
              ),
              const SizedBox(height: 16),
              Text(
                '${matches.length} MATCH${matches.length == 1 ? '' : 'ES'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 8),
              if (matches.isEmpty)
                const _EmptySchedule()
              else
                ...matches.map(
                  (match) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MatchScheduleCard(
                      match: match,
                      guide: data.guide,
                      onManageLines: () => _manageLines(match),
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
      appBar: AppBar(title: const Text('TV Schedule')),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.guide,
    required this.guideError,
    required this.onRefresh,
  });

  final TvScheduleGuide? guide;
  final String? guideError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final guided = guide?.channels.where((channel) => channel.hasGuide).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'TV Schedule',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh TV schedule',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Shows only My Channels TV lines and guide matches. Soco, YYZB, Fawa and ColaTV are excluded.',
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 10),
            if (guideError != null)
              Text(
                'Saved TV lines are still available. $guideError',
                style: TextStyle(color: colors.error, fontSize: 12),
              )
            else if (guide != null)
              Text(
                '${guided ?? 0} catalog channels have a checked TV guide • Myanmar Time (MMT)',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchScheduleCard extends StatelessWidget {
  const _MatchScheduleCard({
    required this.match,
    required this.guide,
    required this.onManageLines,
  });

  final Map<String, dynamic> match;
  final TvScheduleGuide? guide;
  final VoidCallback onManageLines;

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
    final lines = List<String>.from(
      match['_tv_lines'] ?? const <String>[],
    );
    final airings = guide?.airingsForMatch({
          ...match,
          'home_team': home,
          'away_team': away,
        }) ??
        const <TvScheduleAiring>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    league,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(isLive: match['is_live'] == true),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$home vs $away',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(
              kickoff == null
                  ? 'Kickoff time unavailable'
                  : DateFormat('EEE, d MMM • h:mm a', 'en_US')
                      .format(_yangon(kickoff)),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const Divider(height: 26),
            _SectionLabel(
              icon: Icons.tv_rounded,
              text: 'SAVED TV CHANNEL LINES',
            ),
            const SizedBox(height: 7),
            if (lines.isEmpty)
              Text(
                'No My Channels line is attached yet.',
                style: TextStyle(color: colors.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final line in lines)
                    Chip(
                      avatar: const Icon(Icons.tv_rounded, size: 16),
                      label: Text(line),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            _SectionLabel(
              icon: Icons.calendar_month_rounded,
              text: 'LIVE TV GUIDE MATCHES',
            ),
            const SizedBox(height: 7),
            if (guide == null)
              Text(
                'TV guide is unavailable right now.',
                style: TextStyle(color: colors.onSurfaceVariant),
              )
            else if (airings.isEmpty)
              Text(
                'No confirmed channel schedule matches this kickoff yet.',
                style: TextStyle(color: colors.onSurfaceVariant),
              )
            else
              ...airings.map(
                (airing) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _AiringRow(airing: airing),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onManageLines,
                icon: Icon(
                  lines.isEmpty
                      ? Icons.add_link_rounded
                      : Icons.tune_rounded,
                ),
                label: Text(lines.isEmpty ? 'ADD TV LINE' : 'MANAGE TV LINES'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ],
      );
}

class _AiringRow extends StatelessWidget {
  const _AiringRow({required this.airing});

  final TvScheduleAiring airing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            airing.channel,
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            "Live guide • ${DateFormat('h:mm a', 'en_US').format(_yangon(airing.when))} MMT${airing.region.isEmpty ? '' : ' • ${airing.region.toUpperCase()}'}",
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: (isLive ? colors.error : colors.primary).withValues(alpha: .13),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        isLive ? 'LIVE' : 'SCHEDULED',
        style: TextStyle(
          color: isLive ? colors.error : colors.primary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.event_busy_rounded, size: 34),
              const SizedBox(height: 10),
              const Text(
                'No matches in this view.',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                'Choose All to manage older or unpublished matches too.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
