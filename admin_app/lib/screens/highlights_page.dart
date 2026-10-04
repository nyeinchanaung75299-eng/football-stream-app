import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HighlightsPage extends StatefulWidget {
  const HighlightsPage({super.key});

  @override
  State<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends State<HighlightsPage> {
  final title = TextEditingController();
  final thumbnail = TextEditingController();
  final video = TextEditingController();
  bool loading = false;

  Future<void> save() async {
    if (title.text.trim().isEmpty || video.text.trim().isEmpty) return;
    setState(() => loading = true);
    try {
      await Supabase.instance.client.from('highlights').insert({
        'title': title.text.trim(),
        'thumbnail_url':
            thumbnail.text.trim().isEmpty ? null : thumbnail.text.trim(),
        'video_url': video.text.trim(),
        'is_active': true,
      });
      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights Management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: thumbnail,
            decoration: const InputDecoration(labelText: 'Thumbnail URL'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: video,
            decoration: const InputDecoration(labelText: 'Video URL'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: loading ? null : save,
              child: const Text('UPLOAD HIGHLIGHT'),
            ),
          ),
        ],
      ),
    );
  }
}
