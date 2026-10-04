import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLinksPage extends StatefulWidget {
  const LiveLinksPage({super.key});

  @override
  State<LiveLinksPage> createState() => _LiveLinksPageState();
}

class _LiveLinksPageState extends State<LiveLinksPage> {
  final label = TextEditingController(text: 'Main');
  final url = TextEditingController();
  String type = 'hls';
  String? matchId;
  bool loading = false;

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('id,home_team,away_team,league')
        .order('kickoff_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> save() async {
    if (matchId == null || url.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      await Supabase.instance.client.from('stream_links').insert({
        'match_id': matchId,
        'label': label.text.trim().isEmpty ? 'Main' : label.text.trim(),
        'stream_type': type,
        'stream_url': url.text.trim(),
        'is_active': true,
      });
      url.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream link uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Live Links')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadMatches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final matches = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: matchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select Match'),
                items: matches
                    .map(
                      (m) => DropdownMenuItem(
                        value: m['id'] as String,
                        child: Text(
                          '${m['home_team']} vs ${m['away_team']} • ${m['league']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => matchId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: type,
                      decoration:
                          const InputDecoration(labelText: 'Stream Type'),
                      items: const [
                        DropdownMenuItem(value: 'hls', child: Text('HLS (.m3u8)')),
                        DropdownMenuItem(value: 'dash', child: Text('DASH (.mpd)')),
                      ],
                      onChanged: (v) => setState(() => type = v ?? 'hls'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: label,
                      decoration:
                          const InputDecoration(labelText: 'Link Label'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: url,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Stream URL',
                  hintText: 'https://.../stream.m3u8 or manifest.mpd',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: loading ? null : save,
                  icon: const Icon(Icons.link),
                  label: Text(loading ? 'SAVING...' : 'UPLOAD LINK'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
