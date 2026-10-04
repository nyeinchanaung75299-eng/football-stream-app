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
          content: Text(
            useWebView ? 'WebView URL is required.' : 'Stream link is required.',
          ),
        ),
      );
      return;
    }

    setState(() => loading = true);
    try {
      await Supabase.instance.client.from('stream_links').insert({
        'match_id': matchId,
        'label': resolution.text.trim().isEmpty ? 'Auto' : resolution.text.trim(),
        'resolution':
            resolution.text.trim().isEmpty ? 'Auto' : resolution.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Live Link')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: loadMatches(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final matches = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: colors.primary),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Text(
                        'Supports HLS, MPD/DASH, your authorized ClearKey, and WebView links.',
                        style: TextStyle(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Panel(
                title: 'Source',
                icon: Icons.live_tv_rounded,
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: matchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select match',
                        prefixIcon: Icon(Icons.sports_soccer_rounded),
                      ),
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
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: resolution,
                            decoration: const InputDecoration(
                              labelText: 'Resolution',
                              hintText: 'Auto / 720p / 1080p',
                              prefixIcon: Icon(Icons.hd_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: streamType,
                            decoration: const InputDecoration(
                              labelText: 'Player type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'hls',
                                child: Text('HLS'),
                              ),
                              DropdownMenuItem(
                                value: 'dash',
                                child: Text('MPD / DASH'),
                              ),
                            ],
                            onChanged: useWebView
                                ? null
                                : (v) =>
                                    setState(() => streamType = v ?? 'dash'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    TextField(
                      controller: link,
                      minLines: 2,
                      maxLines: 4,
                      enabled: !useWebView,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Stream link',
                        hintText: 'https://...m3u8 or ...manifest.mpd',
                        prefixIcon: Icon(Icons.link_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: 'Headers',
                icon: Icons.http_rounded,
                child: Column(
                  children: [
                    TextField(
                      controller: referer,
                      decoration: const InputDecoration(
                        labelText: 'Referer',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.reply_all_rounded),
                      ),
                    ),
                    const SizedBox(height: 13),
                    TextField(
                      controller: origin,
                      decoration: const InputDecoration(
                        labelText: 'Origin',
                        hintText: 'Optional',
                        prefixIcon: Icon(Icons.public_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: 'ClearKey (optional)',
                icon: Icons.key_rounded,
                subtitle: 'Use only for streams you are authorized to play.',
                child: Column(
                  children: [
                    TextField(
                      controller: keyId,
                      enabled: !useWebView && streamType == 'dash',
                      decoration: const InputDecoration(
                        labelText: 'keyID',
                        hintText: 'Leave blank for non-DRM',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                      ),
                    ),
                    const SizedBox(height: 13),
                    TextField(
                      controller: keyData,
                      enabled: !useWebView && streamType == 'dash',
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'keyData',
                        hintText: 'Leave blank for non-DRM',
                        prefixIcon: Icon(Icons.password_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: 'Playback mode',
                icon: Icons.tune_rounded,
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Use WebView',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        useWebView
                            ? 'Web page player mode'
                            : 'Native HLS / MPD player mode',
                      ),
                      value: useWebView,
                      onChanged: (v) => setState(() => useWebView = v),
                    ),
                    if (useWebView) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: webViewUrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'WebView URL',
                          prefixIcon: Icon(Icons.language_rounded),
                        ),
                      ),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Player notification',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'Show media playback notification when supported.',
                      ),
                      value: sendNotification,
                      onChanged: (v) =>
                          setState(() => sendNotification = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: loading ? null : save,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(loading ? 'UPLOADING...' : 'UPLOAD LINK'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 15),
            child,
          ],
        ),
      ),
    );
  }
}
