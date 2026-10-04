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
  Future<List<Map<String, dynamic>>> load() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,league,home_team,away_team,home_logo_url,away_logo_url,'
          'kickoff_at,sort_order,is_live,is_active',
        )
        .order('kickoff_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> deleteMatch(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete match?'),
        content: const Text(
          'The match and all of its stream links will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
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
    final homeLogo =
        TextEditingController(text: '${m['home_logo_url'] ?? ''}');
    final awayLogo =
        TextEditingController(text: '${m['away_logo_url'] ?? ''}');
    final order =
        TextEditingController(text: '${m['sort_order'] ?? 0}');

    DateTime kickoff = DateTime.parse(m['kickoff_at']).toLocal();
    bool live = m['is_live'] == true;
    bool active = m['is_active'] == true;

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
                firstDate: DateTime.now().subtract(
                  const Duration(days: 3650),
                ),
                lastDate: DateTime.now().add(
                  const Duration(days: 3650),
                ),
              );

              if (result != null) {
                setSheetState(() {
                  kickoff = DateTime(
                    result.year,
                    result.month,
                    result.day,
                    kickoff.hour,
                    kickoff.minute,
                  );
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
                  kickoff = DateTime(
                    kickoff.year,
                    kickoff.month,
                    kickoff.day,
                    result.hour,
                    result.minute,
                  );
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
                        const Expanded(
                          child: Text(
                            'Edit Match',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: league,
                      decoration: const InputDecoration(
                        labelText: 'League',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: home,
                      decoration: const InputDecoration(
                        labelText: 'Home team',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: away,
                      decoration: const InputDecoration(
                        labelText: 'Away team',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: homeLogo,
                      decoration: const InputDecoration(
                        labelText: 'Home logo URL',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: awayLogo,
                      decoration: const InputDecoration(
                        labelText: 'Away logo URL',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickDate,
                            icon: const Icon(Icons.calendar_month_rounded),
                            label: Text(
                              DateFormat('dd MMM yyyy').format(kickoff),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickTime,
                            icon: const Icon(Icons.schedule_rounded),
                            label: Text(
                              DateFormat('HH:mm').format(kickoff),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: order,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Display order',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('LIVE'),
                      value: live,
                      onChanged: (v) =>
                          setSheetState(() => live = v),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: (v) =>
                          setSheetState(() => active = v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.pop(sheetContext, true),
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

    if (league.text.trim().isEmpty ||
        home.text.trim().isEmpty ||
        away.text.trim().isEmpty) {
      message('League and team names cannot be empty.');
      return;
    }

    await Supabase.instance.client
        .from('matches')
        .update({
          'league': league.text.trim(),
          'home_team': home.text.trim(),
          'away_team': away.text.trim(),
          'home_logo_url':
              homeLogo.text.trim().isEmpty ? null : homeLogo.text.trim(),
          'away_logo_url':
              awayLogo.text.trim().isEmpty ? null : awayLogo.text.trim(),
          'kickoff_at': kickoff.toUtc().toIso8601String(),
          'sort_order': int.tryParse(order.text) ?? 0,
          'is_live': live,
          'is_active': active,
        })
        .eq('id', m['id']);

    if (mounted) {
      message('Match updated.');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Matches')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = snapshot.data!;

          if (rows.isEmpty) {
            return const Center(
              child: Text('No matches yet.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final m = rows[index];
              final kickoff = DateTime.parse(m['kickoff_at']).toLocal();
              final live = m['is_live'] == true;
              final active = m['is_active'] == true;

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .5),
                  ),
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
                              color: (live ? Colors.red : colors.primary)
                                  .withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              live
                                  ? Icons.podcasts_rounded
                                  : Icons.sports_soccer_rounded,
                              color: live
                                  ? Colors.redAccent
                                  : colors.primary,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['home_team']} vs ${m['away_team']}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${m['league']} • '
                                  '${DateFormat('dd MMM, HH:mm').format(kickoff)}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                editMatch(m);
                              } else if (value == 'links') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveLinksPage(
                                      initialMatchId: m['id'] as String,
                                    ),
                                  ),
                                );
                              } else if (value == 'delete') {
                                deleteMatch(m['id'] as String);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit_rounded),
                                  title: Text('Edit match'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'links',
                                child: ListTile(
                                  leading: Icon(Icons.link_rounded),
                                  title: Text('Manage links'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.redAccent,
                                  ),
                                  title: Text('Delete match'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _StatusChip(
                            label: live ? 'LIVE' : 'Not live',
                            active: live,
                            activeColor: Colors.redAccent,
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: active ? 'Active' : 'Hidden',
                            active: active,
                            activeColor: colors.primary,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => editMatch(m),
                            icon: const Icon(Icons.edit_calendar_rounded),
                            label: const Text('EDIT'),
                          ),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.active,
    required this.activeColor,
  });

  final String label;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? activeColor.withValues(alpha: .1)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: active ? activeColor : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
