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
  Future<List<Map<String, dynamic>>>? _guide;
  String? openingId;

  Future<List<Map<String, dynamic>>> _loadGuide() async {
    try {
      return await service.listEpgFixtureChannels();
    } catch (_) {
      // Keep ordinary channel-name search usable if EPG is unavailable.
      return <Map<String, dynamic>>[];
    }
  }

  Widget _channelResults(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Text(search.text.trim().isEmpty
            ? 'No channels yet.'
            : 'No matching channels or verified TV schedule.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final image = row['image_url']?.toString() ?? '';
        final fixture = row['epg_fixture']?.toString();
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
            subtitle: Text(fixture == null
                ? '${row['category'] ?? ''}${row['is_active'] == false ? ' • Hidden' : ''}'
                : 'EPG • $fixture${row['is_active'] == false ? ' • Hidden' : ''}'),
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
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> choose(Map<String, dynamic> row) async {
    if (openingId != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
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
              onChanged: (value) {
                if (value.trim().isNotEmpty) {
                  _guide ??= _loadGuide();
                }
                setState(() {});
              },
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
            final query = search.text.trim();
            if (query.isEmpty) {
              return _channelResults(snapshot.data!);
            }
            return FutureBuilder<List<Map<String, dynamic>>>(
              future: _guide ??= _loadGuide(),
              builder: (context, guideSnapshot) {
                final rows = searchChannelsWithEpg(
                    snapshot.data!, guideSnapshot.data ?? [], query);
                if (rows.isEmpty && !guideSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _channelResults(rows);
              },
            );
          },
        ),
      );
}
