import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'player_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Football Live',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadMatches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final matches = snapshot.data!;
          if (matches.isEmpty) {
            return const Center(child: Text('No active matches.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              // Pull-to-refresh works by rebuilding through Navigator replacement.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomePage()),
              );
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              itemCount: matches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final m = matches[index];
                final kickoff = DateTime.parse(m['kickoff_at']).toLocal();
                final links = List<Map<String, dynamic>>.from(
                  m['stream_links'] ?? const [],
                ).where((x) => x['is_active'] == true).toList();

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m['league'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (m['is_live'] == true)
                              const Chip(
                                label: Text('LIVE'),
                                avatar: Icon(Icons.circle, size: 12),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _Team(
                                name: m['home_team'],
                                logo: m['home_logo_url'],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'VS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _Team(
                                name: m['away_team'],
                                logo: m['away_logo_url'],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(DateFormat('EEE, dd MMM • HH:mm').format(kickoff)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: links.isEmpty
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlayerPage(
                                          title:
                                              '${m['home_team']} vs ${m['away_team']}',
                                          links: links,
                                        ),
                                      ),
                                    ),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(
                              links.isEmpty ? 'NO STREAM' : 'WATCH LIVE',
                            ),
                          ),
                        ),
                      ],
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

class _Team extends StatelessWidget {
  const _Team({required this.name, required this.logo});

  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundImage:
              (logo != null && logo!.isNotEmpty) ? NetworkImage(logo!) : null,
          child: (logo == null || logo!.isEmpty)
              ? const Icon(Icons.shield_outlined)
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
