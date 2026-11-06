import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChannelReportsPage extends StatefulWidget {
  const ChannelReportsPage({super.key});
  @override
  State<ChannelReportsPage> createState() => _ChannelReportsPageState();
}

class _ChannelReportsPageState extends State<ChannelReportsPage> {
  late Future<List<Map<String, dynamic>>> reports = _load();
  Future<List<Map<String, dynamic>>> _load() async => List<Map<String, dynamic>>.from(
    await Supabase.instance.client.from('nca_viewer_reports')
      .select('id,created_at,channels(name),channel_lines(label)')
      .order('created_at', ascending: false).limit(100)
      .timeout(const Duration(seconds: 15)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Viewer line reports'), actions: [
      IconButton(tooltip: 'Refresh reports', onPressed: () => setState(() => reports = _load()),
        icon: const Icon(Icons.refresh_rounded)),
    ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: reports, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: FilledButton(
        onPressed: () => setState(() => reports = _load()), child: const Text('RETRY')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final rows = snapshot.data!;
      if (rows.isEmpty) return const Center(child: Text('No line reports yet.'));
      return ListView.builder(itemCount: rows.length, itemBuilder: (_, i) {
        final row = rows[i];
        final channel = row['channels'] as Map?;
        final line = row['channel_lines'] as Map?;
        final at = DateTime.tryParse(row['created_at'].toString());
        return ListTile(leading: const Icon(Icons.flag_outlined),
          title: Text(channel?['name']?.toString() ?? 'Channel'),
          subtitle: Text('${line?['label'] ?? 'Line'} • ${at == null ? '' : DateFormat('dd MMM, h:mm a').format(at.toLocal())}'));
      });
    }),
  );
}
