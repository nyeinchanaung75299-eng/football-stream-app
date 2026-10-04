import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditLivePage extends StatefulWidget {
  const EditLivePage({super.key});

  @override
  State<EditLivePage> createState() => _EditLivePageState();
}

class _EditLivePageState extends State<EditLivePage> {
  Future<List<Map<String, dynamic>>> load() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('id,league,home_team,away_team,is_live,is_active,kickoff_at')
        .order('kickoff_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> setFlags(
    String id, {
    bool? live,
    bool? active,
  }) async {
    final patch = <String, dynamic>{};
    if (live != null) patch['is_live'] = live;
    if (active != null) patch['is_active'] = active;
    await Supabase.instance.client.from('matches').update(patch).eq('id', id);
    setState(() {});
  }

  Future<void> deleteMatch(String id) async {
    await Supabase.instance.client.from('matches').delete().eq('id', id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Live Matches')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sports_soccer_outlined,
                      size: 58,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No matches yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final m = rows[index];
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (live ? Colors.red : colors.primary)
                                  .withValues(alpha: .11),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              live
                                  ? Icons.podcasts_rounded
                                  : Icons.sports_soccer_rounded,
                              color: live ? Colors.redAccent : colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['home_team']}  vs  ${m['away_team']}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${m['league']}',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            color: Colors.redAccent,
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Delete match?'),
                                  content: const Text(
                                    'Its stream links will also be deleted.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await deleteMatch(m['id']);
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('LIVE'),
                              value: live,
                              onChanged: (v) => setFlags(m['id'], live: v),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active'),
                              value: active,
                              onChanged: (v) => setFlags(m['id'], active: v),
                            ),
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
