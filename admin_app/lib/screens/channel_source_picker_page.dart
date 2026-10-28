import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/channel_source_service.dart';
import '../widgets/channel_search_field.dart';

class ChannelSourcePickerPage extends StatefulWidget {
  const ChannelSourcePickerPage({super.key});
  @override
  State<ChannelSourcePickerPage> createState() =>
      _ChannelSourcePickerPageState();
}

class _ChannelSourcePickerPageState extends State<ChannelSourcePickerPage> {
  final search = TextEditingController();
  late final service = ChannelSourceService(Supabase.instance.client);
  late Future<List<Map<String, dynamic>>> catalog = service.list();
  String? openingId;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> choose(Map<String, dynamic> row) async {
    if (openingId != null) return;
    setState(() => openingId = row['id'].toString());
    try {
      final selected = await service.select(row);
      if (mounted) Navigator.of(context).pop(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not load this channel. Try another channel or retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Choose channel'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: ChannelSearchField(
              controller: search,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => catalog = service.list()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Could not load channels. Retry'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!
                .where((r) => channelMatchesSearch(r, search.text))
                .toList();
            if (rows.isEmpty) {
              return Center(
                  child: Text(search.text.trim().isEmpty
                      ? 'No channels yet.'
                      : 'No matching channels.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                final image = row['image_url']?.toString() ?? '';
                return Card(
                  child: ListTile(
                    enabled: openingId == null,
                    leading: image.startsWith('https://')
                        ? Image.network(image,
                            width: 52,
                            height: 42,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv))
                        : const Icon(Icons.tv),
                    title: Text(row['name']?.toString() ?? 'Channel'),
                    subtitle: Text(
                        '${row['category'] ?? ''}${row['is_active'] == false ? ' • Hidden' : ''}'),
                    trailing: openingId == row['id'].toString()
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_link),
                    onTap: () => choose(row),
                  ),
                );
              },
            );
          },
        ),
      );
}
