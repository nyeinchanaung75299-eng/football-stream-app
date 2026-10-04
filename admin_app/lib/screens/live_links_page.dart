import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLinksPage extends StatefulWidget {
  const LiveLinksPage({super.key});

  @override
  State<LiveLinksPage> createState() => _LiveLinksPageState();
}

class _LiveLinksPageState extends State<LiveLinksPage> {
  final resolution = TextEditingController(text: 'Auto');
  final link = TextEditingController();
  final referer = TextEditingController();
  final origin = TextEditingController();
  final keyId = TextEditingController();
  final keyData = TextEditingController();
  final webViewUrl = TextEditingController();

  String streamType = 'dash';
  String? matchId;
  bool useWebView = false;
  bool sendNotification = false;
  bool loading = false;

  Future<List<Map<String, dynamic>>> loadMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select('id,home_team,away_team,league')
        .order('kickoff_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> save() async {
    if (matchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a match first.')),
      );
      return;
    }

    final mediaUrl = link.text.trim();
    final browserUrl = webViewUrl.text.trim();
    if ((!useWebView && mediaUrl.isEmpty) || (useWebView && browserUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(useWebView ? 'WebView URL is required.' : 'Link is required.'),
        ),
      );
      return;
    }

    setState(() => loading = true);
    try {
      await Supabase.instance.client.from('stream_links').insert({
        'match_id': matchId,
        'label': resolution.text.trim().isEmpty ? 'Auto' : resolution.text.trim(),
        'resolution': resolution.text.trim().isEmpty ? 'Auto' : resolution.text.trim(),
        'stream_type': streamType,
        'stream_url': mediaUrl,
        'referer': referer.text.trim().isEmpty ? null : referer.text.trim(),
        'origin': origin.text.trim().isEmpty ? null : origin.text.trim(),
        'key_id': keyId.text.trim().isEmpty ? null : keyId.text.trim(),
        'key_data': keyData.text.trim().isEmpty ? null : keyData.text.trim(),
        'use_webview': useWebView,
        'webview_url': browserUrl.isEmpty ? null : browserUrl,
        'send_notification': sendNotification,
        'is_active': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live link uploaded.')),
      );

      link.clear();
      referer.clear();
      origin.clear();
      keyId.clear();
      keyData.clear();
      webViewUrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget gap() => const SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Links Upload')),
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
              gap(),
              TextField(
                controller: resolution,
                decoration: const InputDecoration(labelText: 'Resolution'),
              ),
              gap(),
              DropdownButtonFormField<String>(
                value: streamType,
                decoration: const InputDecoration(labelText: 'Player Type'),
                items: const [
                  DropdownMenuItem(value: 'hls', child: Text('HLS (.m3u8)')),
                  DropdownMenuItem(value: 'dash', child: Text('MPD / DASH (.mpd)')),
                ],
                onChanged: useWebView
                    ? null
                    : (v) => setState(() => streamType = v ?? 'dash'),
              ),
              gap(),
              TextField(
                controller: link,
                minLines: 2,
                maxLines: 4,
                enabled: !useWebView,
                decoration: const InputDecoration(
                  labelText: 'Link',
                  hintText: 'https://...m3u8 or https://...manifest.mpd',
                ),
              ),
              gap(),
              TextField(
                controller: referer,
                decoration: const InputDecoration(
                  labelText: 'Referer',
                  hintText: 'Optional HTTP Referer header',
                ),
              ),
              gap(),
              TextField(
                controller: origin,
                decoration: const InputDecoration(
                  labelText: 'Origin',
                  hintText: 'Optional HTTP Origin header',
                ),
              ),
              gap(),
              TextField(
                controller: keyId,
                enabled: !useWebView && streamType == 'dash',
                decoration: const InputDecoration(
                  labelText: 'keyID',
                  hintText: 'ClearKey KID in HEX; leave blank for non-DRM',
                ),
              ),
              gap(),
              TextField(
                controller: keyData,
                enabled: !useWebView && streamType == 'dash',
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'keyData',
                  hintText: 'ClearKey key in HEX; leave blank for non-DRM',
                ),
              ),
              gap(),
              TextField(
                controller: webViewUrl,
                enabled: useWebView,
                decoration: const InputDecoration(
                  labelText: 'webView',
                  hintText: 'https://example.com/player',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('MPD or WebView'),
                subtitle: Text(useWebView ? 'WebView mode' : 'Media player mode'),
                value: useWebView,
                onChanged: (v) => setState(() => useWebView = v),
              ),
              SwitchListTile(
                title: const Text('Notification Send'),
                value: sendNotification,
                onChanged: (v) => setState(() => sendNotification = v),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: loading ? null : save,
                  child: Text(loading ? 'UPLOADING...' : 'UPLOAD'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
