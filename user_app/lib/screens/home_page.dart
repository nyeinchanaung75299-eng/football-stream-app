import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/theme_mode_button.dart';
import 'player_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = loadMatches();
  }

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('''
          id,league,home_team,away_team,home_logo_url,away_logo_url,
          kickoff_at,is_live,sort_order,
          stream_links(id,label,resolution,stream_type,stream_url,referer,origin,key_id,key_data,use_webview,webview_url,send_notification,is_active,sort_order)
        ''')
        .eq('is_active', true)
        .order('sort_order')
        .order('kickoff_at');

    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> refresh() async {
    final next = loadMatches();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer_rounded, size: 25),
            SizedBox(width: 9),
            Text('Football Live'),
          ],
        ),
        actions: const [
          ThemeModeButton(),
          SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.wifi_off_rounded,
              title: 'Couldn’t load matches',
              subtitle: 'Can’t reach the server. Turn on VPN and try again.',
              action: 'TRY AGAIN',
              onPressed: refresh,
            );
          }

          final matches = snapshot.data ?? const [];
          if (matches.isEmpty) {
            return _StateMessage(
              icon: Icons.sports_soccer_outlined,
              title: 'No active matches',
              subtitle: 'New matches will appear here when the admin uploads them.',
              action: 'REFRESH',
              onPressed: refresh,
            );
          }

          final liveCount =
              matches.where((m) => m['is_live'] == true).length;

          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
              itemCount: matches.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _TopBanner(
                    liveCount: liveCount,
                    totalCount: matches.length,
                  );
                }

                final m = matches[index - 1];
                final kickoff = DateTime.parse(m['kickoff_at']).toLocal();
                final links = List<Map<String, dynamic>>.from(
                  m['stream_links'] ?? const [],
                ).where((x) => x['is_active'] == true).toList();

                return _MatchCard(
                  league: (m['league'] ?? '').toString(),
                  homeTeam: (m['home_team'] ?? '').toString(),
                  awayTeam: (m['away_team'] ?? '').toString(),
                  homeLogo: m['home_logo_url']?.toString(),
                  awayLogo: m['away_logo_url']?.toString(),
                  kickoff: kickoff,
                  isLive: m['is_live'] == true,
                  serverCount: links.length,
                  onWatch: links.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlayerPage(
                                title:
                                    '${m['home_team']} vs ${m['away_team']}',
                                subtitle: (m['league'] ?? '').toString(),
                                links: links,
                              ),
                            ),
                          ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({
    required this.liveCount,
    required this.totalCount,
  });

  final int liveCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0B5633),
            Color(0xFF11A861),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF11A861).withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.live_tv_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Football',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$liveCount live • $totalCount active match${totalCount == 1 ? '' : 'es'}',
                  style: const TextStyle(
                    color: Color(0xFFE5F8ED),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white70,
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeLogo,
    required this.awayLogo,
    required this.kickoff,
    required this.isLive,
    required this.serverCount,
    required this.onWatch,
  });

  final String league;
  final String homeTeam;
  final String awayTeam;
  final String? homeLogo;
  final String? awayLogo;
  final DateTime kickoff;
  final bool isLive;
  final int serverCount;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    league,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: Colors.redAccent,
                          size: 8,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      DateFormat('HH:mm').format(kickoff),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _Team(
                    name: homeTeam,
                    logo: homeLogo,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Text(
                        'VS',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        DateFormat('dd MMM').format(kickoff),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _Team(
                    name: awayTeam,
                    logo: awayLogo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$serverCount server${serverCount == 1 ? '' : 's'} available',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: onWatch,
                    icon: const Icon(Icons.play_arrow_rounded, size: 21),
                    label: Text(
                      onWatch == null ? 'NO STREAM' : 'WATCH',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({
    required this.name,
    required this.logo,
  });

  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasLogo = logo != null && logo!.trim().isNotEmpty;

    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(21),
          ),
          child: hasLogo
              ? Image.network(
                  logo!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.shield_outlined,
                    size: 34,
                  ),
                )
              : const Icon(
                  Icons.shield_outlined,
                  size: 34,
                ),
        ),
        const SizedBox(height: 9),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 62, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                height: 1.4,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onPressed,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}
