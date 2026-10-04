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
    if (title.text.trim().isEmpty || video.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and video URL are required.')),
      );
      return;
    }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Highlight uploaded.')),
      );
      Navigator.pop(context);
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
      appBar: AppBar(title: const Text('Highlights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Highlight title',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    controller: thumbnail,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Thumbnail URL',
                      prefixIcon: Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    controller: video,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Video URL',
                      prefixIcon: Icon(Icons.play_circle_outline_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : save,
            icon: const Icon(Icons.cloud_upload_rounded),
            label: Text(loading ? 'UPLOADING...' : 'UPLOAD HIGHLIGHT'),
          ),
        ],
      ),
    );
  }
}
