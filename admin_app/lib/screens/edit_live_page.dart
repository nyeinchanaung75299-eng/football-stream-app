import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_links_page.dart';
import '../analytics_service.dart';

class EditLivePage extends StatefulWidget {
  const EditLivePage({super.key});

  @override
  State<EditLivePage> createState() => _EditLivePageState();
}

class _EditLivePageState extends State<EditLivePage> {
  String view = 'upcoming';
  late Future<List<Map<String, dynamic>>> _matchesFuture;

  @override
  void initState() {
    super.initState();
    _matchesFuture = load();
  }

  void reloadMatches() {
    if (!mounted) return;
    setState(() { _matchesFuture = load(); });
  }

  String sectionLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final diff = day.difference(today).inDays;

    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'TOMORROW';
    if (diff == -1) return 'YESTERDAY';
    return DateFormat('EEE, dd MMM yyyy').format(value).toUpperCase();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,league,home_team,away_team,home_logo_url,away_logo_url,'
          'kickoff_at,sort_order,is_live,is_active,is_featured,publish_state,'
          'deleted_at',
        )
        .timeout(const Duration(seconds: 8));

    final rows = List<Map<String, dynamic>>.from(data)
        .where((row) => row['deleted_at'] == null)
        .toList();

    rows.sort((a, b) {
      final aTime = DateTime.tryParse(a['kickoff_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime(9999);
      final bTime = DateTime.tryParse(b['kickoff_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime(9999);

      final byTime = aTime.compareTo(bTime);
      if (byTime != 0) return byTime;

      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      final byOrder = aOrder.compareTo(bOrder);
      if (byOrder != 0) return byOrder;

      final aName = (a['home_team'] ?? '').toString().toLowerCase();
      final bName = (b['home_team'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return rows;
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> deleteMatch(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete match?'),
        content: const Text(
          'The match will be hidden permanently from imports and all of its stream links will be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('matches').update({
        'is_active': false,
        'is_featured': false,
        'is_live': false,
        'publish_state': 'draft',
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      await Supabase.instance.client
          .from('stream_links')
          .delete()
          .eq('match_id', id);

      await AnalyticsService.capture(
        'match deleted',
        properties: {'match_id': id},
      );

      if (mounted) {
        message('Match deleted. It will not be re-imported automatically.');
        reloadMatches();
      }
    } catch (e) {
      await AnalyticsService.capture(
        'match delete failed',
        properties: {'match_id': id},
      );
      if (mounted) message('Delete failed: $e');
    }
  }

  Future<void> editMatch(Map<String, dynamic> m) async {
    final league = TextEditingController(text: '${m['league'] ?? ''}');
    final home = TextEditingController(text: '${m['home_team'] ?? ''}');
    final away = TextEditingController(text: '${m['away_team'] ?? ''}');
    final homeLogo = TextEditingController(text: '${m['home_logo_url'] ?? ''}');
    final awayLogo = TextEditingController(text: '${m['away_logo_url'] ?? ''}');
    final order = TextEditingController(text: '${m['sort_order'] ?? 0}');
    DateTime kickoff = DateTime.parse(m['kickoff_at']).toLocal();
    bool live = m['is_live'] == true;
    bool active = m['is_active'] == true;
    bool featured = m['is_featured'] != false;
    bool published = (m['publish_state'] ?? 'published') == 'published';

    void disposeEditors() {
      for (final controller in [league, home, away, homeLogo, awayLogo, order]) {
        controller.dispose();
      }
    }

    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickDate() async {
              final result = await showDatePicker(
                context: context,
                initialDate: kickoff,
                firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (result != null) {
                setSheetState(() {
                  kickoff = DateTime(result.year, result.month, result.day, kickoff.hour, kickoff.minute);
                });
              }
            }

            Future<void> pickTime() async {
              final result = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(kickoff),
              );
              if (result != null) {
                setSheetState(() {
                  kickoff = DateTime(kickoff.year, kickoff.month, kickoff.day, result.hour, result.minute);
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('Edit Match', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                        IconButton(onPressed: () => Navigator.pop(sheetContext, false), icon: const Icon(Icons.close_rounded)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: league, decoration: const InputDecoration(labelText: 'League')),
                    const SizedBox(height: 12),
                    TextField(controller: home, decoration: const InputDecoration(labelText: 'Home team')),
                    const SizedBox(height: 12),
                    TextField(controller: away, decoration: const InputDecoration(labelText: 'Away team')),
                    const SizedBox(height: 12),
                    TextField(controller: homeLogo, decoration: const InputDecoration(labelText: 'Home logo URL')),
                    const SizedBox(height: 12),
                    TextField(controller: awayLogo, decoration: const InputDecoration(labelText: 'Away logo URL')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: OutlinedButton.icon(onPressed: pickDate, icon: const Icon(Icons.calendar_month_rounded), label: Text(DateFormat('dd MMM yyyy').format(kickoff)))),
                        const SizedBox(width: 10),
                        Expanded(child: OutlinedButton.icon(onPressed: pickTime, icon: const Icon(Icons.schedule_rounded), label: Text(DateFormat('HH:mm').format(kickoff)))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Display order')),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Featured / Big match'),
                      subtitle: const Text('Viewer app lists featured matches only.'),
                      value: featured,
                      onChanged: (v) => setSheetState(() => featured = v),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Published'),
                      subtitle: const Text('Turn off to keep it as a draft.'),
                      value: published,
                      onChanged: (v) => setSheetState(() => published = v),
                    ),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('LIVE'), value: live, onChanged: (v) => setSheetState(() => live = v)),
                    SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v) => setSheetState(() => active = v)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('SAVE MATCH'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (save != true) {
      disposeEditors();
      return;
    }
    if (league.text.trim().isEmpty || home.text.trim().isEmpty || away.text.trim().isEmpty) {
      message('League and team names cannot be empty.');
      disposeEditors();
      return;
    }

    try {
      await Supabase.instance.client.from('matches').update({
        'league': league.text.trim(),
        'home_team': home.text.trim(),
        'away_team': away.text.trim(),
        'home_logo_url':
            homeLogo.text.trim().isEmpty ? null : homeLogo.text.trim(),
        'away_logo_url':
            awayLogo.text.trim().isEmpty ? null : awayLogo.text.trim(),
        'kickoff_at': kickoff.toUtc().toIso8601String(),
        'sort_order': int.tryParse(order.text) ?? 0,
        'is_featured': featured,
        'publish_state': published ? 'published' : 'draft',
        'is_live': live,
        'is_active': active,
      }).eq('id', m['id']);

      await AnalyticsService.capture(
        'match updated',
        properties: {
          'match_id': m['id'].toString(),
          'featured': featured,
          'published': published,
          'is_live': live,
          'is_active': active,
        },
      );

      if (mounted) {
        message('Match updated.');
        reloadMatches();
      }
    } catch (e) {
      await AnalyticsService.capture(
        'match update failed',
        properties: {'match_id': m['id'].toString()},
      );
      if (mounted) message('Match update failed: $e');
    } finally {
      disposeEditors();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Matches'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _matchesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Could not load matches. Check your connection and retry.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: reloadMatches, child: const Text('Retry')),
            ]));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('No matches yet.'));

          final now = DateTime.now();
          final visibleRows = rows.where((m) {
            // Admin "All" is the recovery/edit view: keep every non-deleted
            // match visible even if it was made inactive, unfeatured or draft.
            if (view == 'all') return m['deleted_at'] == null;

            final current =
                m['deleted_at'] == null &&
                m['is_active'] == true &&
                m['is_featured'] != false &&
                (m['publish_state'] ?? 'published') == 'published';
            if (!current) return false;

            if (view == 'live') return m['is_live'] == true;
            if (view == 'upcoming') {
              final kickoff =
                  DateTime.tryParse(m['kickoff_at']?.toString() ?? '')
                      ?.toLocal();
              return m['is_live'] == true ||
                  (kickoff != null && !kickoff.isBefore(now));
            }
            return true;
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
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
                      ButtonSegment(
                        value: 'all',
                        icon: Icon(Icons.list_alt_rounded),
                        label: Text('All'),
                      ),
                    ],
                    selected: {view},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) {
                      setState(() => view = value.first);
                    },
                  ),
                ),
              ),
              Expanded(
                child: visibleRows.isEmpty
                    ? const Center(
                        child: Text('No matches in this section.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                        itemCount: visibleRows.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final m = visibleRows[index];
                          final kickoff =
                              DateTime.parse(m['kickoff_at']).toLocal();
                          final previousKickoff = index == 0
                              ? null
                              : DateTime.parse(
                                  visibleRows[index - 1]['kickoff_at']
                                      .toString(),
                                ).toLocal();
                          final showDateHeader = previousKickoff == null ||
                              previousKickoff.year != kickoff.year ||
                              previousKickoff.month != kickoff.month ||
                              previousKickoff.day != kickoff.day;
              final live = m['is_live'] == true;
              final featured = m['is_featured'] != false;
              final published = (m['publish_state'] ?? 'published') == 'published';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showDateHeader) ...[
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    4,
                                    index == 0 ? 2 : 8,
                                    4,
                                    8,
                                  ),
                                  child: Text(
                                    sectionLabel(kickoff),
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .8,
                                    ),
                                  ),
                                ),
                              ],
                              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (live ? Colors.red : colors.primary).withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              live ? Icons.podcasts_rounded : Icons.sports_soccer_rounded,
                              color: live ? Colors.redAccent : colors.primary,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${m['home_team']} vs ${m['away_team']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text(
                                  '${m['league']} • ${DateFormat('dd MMM, HH:mm').format(kickoff)}',
                                  style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') editMatch(m);
                              if (value == 'links') {
                                AnalyticsService.capture(
                                  'admin section opened',
                                  properties: {
                                    'section': 'stream-servers',
                                    'from': 'match-menu',
                                  },
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    settings: const RouteSettings(
                                      name: '/admin/stream-servers',
                                    ),
                                    builder: (_) => LiveLinksPage(
                                      initialMatchId: m['id'] as String,
                                    ),
                                  ),
                                );
                              }
                              if (value == 'delete') deleteMatch(m['id'] as String);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit match')),
                              PopupMenuItem(value: 'links', child: Text('Manage links')),
                              PopupMenuItem(value: 'delete', child: Text('Delete match')),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _Badge(
                              text: featured ? 'BIG MATCH' : 'HIDDEN',
                              color: featured
                                  ? Colors.amber.shade700
                                  : Colors.blueGrey,
                            ),
                            _Badge(
                              text: published ? 'PUBLISHED' : 'DRAFT',
                              color: published
                                  ? colors.primary
                                  : Colors.blueGrey,
                            ),
                            if (live)
                              const _Badge(
                                text: 'LIVE',
                                color: Colors.redAccent,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveLinksPage(
                                      initialMatchId: m['id'] as String,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.link_rounded, size: 18),
                              label: const Text('STREAMS'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => editMatch(m),
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('EDIT'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10.5)),
    );
  }
}
