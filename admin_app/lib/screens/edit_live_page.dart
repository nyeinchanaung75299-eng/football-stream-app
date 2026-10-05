import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_links_page.dart';

class EditLivePage extends StatefulWidget {
  const EditLivePage({super.key});

  @override
  State<EditLivePage> createState() => _EditLivePageState();
}

class _EditLivePageState extends State<EditLivePage> {
  bool syncing = false;

  Future<List<Map<String, dynamic>>> load() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,league,home_team,away_team,home_logo_url,away_logo_url,'
          'kickoff_at,sort_order,is_live,is_active,is_featured,publish_state,'
          'home_score,away_score,status_short,status_elapsed,external_fixture_id',
        )
        .order('kickoff_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> syncScores() async {
    setState(() => syncing = true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'football-score-sync',
        body: const {'force': true},
      );
      if (!mounted) return;
      final data = res.data;
      if (data is Map && data['synced'] != null) {
        message('Score sync: ${data['synced']} match(es) updated.');
      } else {
        message('Score sync finished.');
      }
      setState(() {});
    } catch (e) {
      if (mounted) message('Score sync failed: $e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> deleteMatch(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete match?'),
        content: const Text('The match and all of its stream links will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await Supabase.instance.client.from('matches').delete().eq('id', id);
    if (mounted) {
      message('Match deleted.');
      setState(() {});
    }
  }

  Future<void> editMatch(Map<String, dynamic> m) async {
    final league = TextEditingController(text: '${m['league'] ?? ''}');
    final home = TextEditingController(text: '${m['home_team'] ?? ''}');
    final away = TextEditingController(text: '${m['away_team'] ?? ''}');
    final homeLogo = TextEditingController(text: '${m['home_logo_url'] ?? ''}');
    final awayLogo = TextEditingController(text: '${m['away_logo_url'] ?? ''}');
    final order = TextEditingController(text: '${m['sort_order'] ?? 0}');
    final homeScore = TextEditingController(text: m['home_score'] == null ? '' : '${m['home_score']}');
    final awayScore = TextEditingController(text: m['away_score'] == null ? '' : '${m['away_score']}');

    DateTime kickoff = DateTime.parse(m['kickoff_at']).toLocal();
    bool live = m['is_live'] == true;
    bool active = m['is_active'] == true;
    bool featured = m['is_featured'] != false;
    bool published = (m['publish_state'] ?? 'published') == 'published';

    int scoreValue(TextEditingController controller) =>
        int.tryParse(controller.text.trim()) ?? 0;

    void changeScore(
      TextEditingController controller,
      int delta,
      void Function(void Function()) setSheetState,
    ) {
      setSheetState(() {
        final next = (scoreValue(controller) + delta).clamp(0, 99);
        controller.text = '$next';
      });
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
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Goal Score',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      home.text.trim().isEmpty
                                          ? 'Home'
                                          : home.text.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    TextField(
                                      controller: homeScore,
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Home score',
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => changeScore(
                                              homeScore,
                                              -1,
                                              setSheetState,
                                            ),
                                            child: const Text('−'),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: () => changeScore(
                                              homeScore,
                                              1,
                                              setSheetState,
                                            ),
                                            child: const Text('+ GOAL'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '—',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      away.text.trim().isEmpty
                                          ? 'Away'
                                          : away.text.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    TextField(
                                      controller: awayScore,
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Away score',
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => changeScore(
                                              awayScore,
                                              -1,
                                              setSheetState,
                                            ),
                                            child: const Text('−'),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: () => changeScore(
                                              awayScore,
                                              1,
                                              setSheetState,
                                            ),
                                            child: const Text('+ GOAL'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            m['external_fixture_id'] == null
                                ? 'Manual match: score is controlled here.'
                                : 'API match: score can auto-sync; manual correction is still allowed.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
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

    if (save != true) return;
    if (league.text.trim().isEmpty || home.text.trim().isEmpty || away.text.trim().isEmpty) {
      message('League and team names cannot be empty.');
      return;
    }

    await Supabase.instance.client.from('matches').update({
      'league': league.text.trim(),
      'home_team': home.text.trim(),
      'away_team': away.text.trim(),
      'home_logo_url': homeLogo.text.trim().isEmpty ? null : homeLogo.text.trim(),
      'away_logo_url': awayLogo.text.trim().isEmpty ? null : awayLogo.text.trim(),
      'kickoff_at': kickoff.toUtc().toIso8601String(),
      'sort_order': int.tryParse(order.text) ?? 0,
      'home_score': int.tryParse(homeScore.text),
      'away_score': int.tryParse(awayScore.text),
      'is_featured': featured,
      'publish_state': published ? 'published' : 'draft',
      'is_live': live,
      'is_active': active,
    }).eq('id', m['id']);

    if (mounted) {
      message('Match updated.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Matches'),
        actions: [
          IconButton(
            tooltip: 'Sync scores',
            onPressed: syncing ? null : syncScores,
            icon: syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) return const Center(child: Text('No matches yet.'));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final m = rows[index];
              final kickoff = DateTime.parse(m['kickoff_at']).toLocal();
              final live = m['is_live'] == true;
              final featured = m['is_featured'] != false;
              final published = (m['publish_state'] ?? 'published') == 'published';
              final hs = m['home_score'];
              final as = m['away_score'];
              final status = (m['status_short'] ?? 'NS').toString();

              return Card(
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
                                  '${m['league']} • ${DateFormat('dd MMM, HH:mm').format(kickoff)}${hs == null || as == null ? '' : ' • $hs-$as'} • $status',
                                  style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') editMatch(m);
                              if (value == 'links') {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => LiveLinksPage(initialMatchId: m['id'] as String)));
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
                      Row(
                        children: [
                          _Badge(text: featured ? 'BIG MATCH' : 'HIDDEN', color: featured ? Colors.amber.shade700 : Colors.blueGrey),
                          const SizedBox(width: 7),
                          _Badge(text: published ? 'PUBLISHED' : 'DRAFT', color: published ? colors.primary : Colors.blueGrey),
                          if (live) ...[
                            const SizedBox(width: 7),
                            const _Badge(text: 'LIVE', color: Colors.redAccent),
                          ],
                          const Spacer(),
                          TextButton(onPressed: () => editMatch(m), child: const Text('EDIT')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
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
