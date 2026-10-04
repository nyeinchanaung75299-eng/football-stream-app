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
    return Scaffold(
      appBar: AppBar(title: const Text('Edit & Delete Live')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return const Center(child: Text('No matches yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = rows[index];
              final live = m['is_live'] == true;
              final active = m['is_active'] == true;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${m['home_team']}  vs  ${m['away_team']}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${m['league']}\n${m['kickoff_at']}'),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('LIVE'),
                              value: live,
                              onChanged: (v) => setFlags(m['id'], live: v),
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active'),
                              value: active,
                              onChanged: (v) => setFlags(m['id'], active: v),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            color: Colors.red,
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
                            icon: const Icon(Icons.delete_outline),
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
