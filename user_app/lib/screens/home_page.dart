import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../native_player.dart';
import '../widgets/theme_mode_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Map<String, dynamic>>> _future;
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _future = loadMatches();
    _channel = Supabase.instance.client
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

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('''
          id,league,home_team,away_team,home_logo_url,away_logo_url,
          kickoff_at,is_live,sort_order,home_score,away_score,status_short,
          status_elapsed,is_finished,is_featured,publish_state,
          stream_links(
            id,label,resolution,stream_type,stream_url,referer,origin,
            key_id,key_data,use_webview,webview_url,is_active,priority,
            available_from,expires_at,health_status
          )
        ''')
        .eq('is_active', true)
        .eq('publish_state', 'published')
        .eq('is_featured', true)
        .order('sort_order')
        .order('kickoff_at');
    return List<Map<String, dynamic>>.from(data);
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

    filtered.sort((a, b) {
      final h = healthRank(a).compareTo(healthRank(b));
      if (h != 0) return h;
      final ap = (a['priority'] as num?)?.toInt() ?? 100;
      final bp = (b['priority'] as num?)?.toInt() ?? 100;
      return ap.compareTo(bp);
    });
    return filtered;
  }

  Future<void> openPlayer(Map<String, dynamic> match) async {
    final links = playableLinks(match['stream_links']);
    if (links.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream is not available yet.')),
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
            })
        .where((x) => (x['url'] as String).trim().isNotEmpty)
        .toList();

    if (nativeSources.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This match currently has no native stream.')),
      );
      return;
    }

    var selectedIndex = 0;

    if (nativeSources.length > 1) {
      final picked = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final colors = Theme.of(sheetContext).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose line',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${match['home_team']} vs ${match['away_team']}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                ...List.generate(nativeSources.length, (index) {
                  final source = nativeSources[index];
                  final label = (source['label'] ?? 'Server ${index + 1}').toString();
                  final type = (source['streamType'] ?? 'auto').toString().toUpperCase();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: .5),
                        ),
                      ),
                      leading: const Icon(Icons.dns_rounded),
                      title: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(type == 'AUTO' ? 'Auto / Direct' : type),
                      trailing: const Icon(Icons.play_arrow_rounded),
                      onTap: () => Navigator.pop(sheetContext, index),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );

      if (picked == null) return;
      selectedIndex = picked;
    }

    try {
      await NativePlayer.open(
        sources: nativeSources,
        selectedIndex: selectedIndex,
        title: '${match['home_team']} vs ${match['away_team']}',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player could not be opened.')),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final c = _channel;
    if (c != null) Supabase.instance.client.removeChannel(c);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer_rounded, size: 24),
            SizedBox(width: 8),
            Text('Football'),
          ],
        ),
        actions: const [ThemeModeButton(), SizedBox(width: 6)],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done && !snapshot.hasData) {
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
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final m = matches[index];
                final links = playableLinks(m['stream_links']);
                return _MatchCard(
                  match: m,
                  canWatch: links.isNotEmpty,
                  linkCount: links.length,
                  onWatch: () => openPlayer(m),
                );
              },
            ),
          );
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
    final homeScore = (match['home_score'] as num?)?.toInt();
    final awayScore = (match['away_score'] as num?)?.toInt();
    final elapsed = (match['status_elapsed'] as num?)?.toInt();
    final showScore = homeScore != null && awayScore != null && (live || finished);

    return Card(
      margin: EdgeInsets.zero,
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
                        ? Text(
                            '$homeScore - $awayScore',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
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
              height: 38,
              child: FilledButton.icon(
                onPressed: canWatch ? onWatch : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  canWatch
                      ? (linkCount > 1 ? 'WATCH • $linkCount LINES' : 'WATCH')
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
