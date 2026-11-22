import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/connected_channel_source.dart';
import '../services/stream_detector_service.dart';
import 'stream_preview_page.dart';

class CombatSportsPage extends StatefulWidget {
  const CombatSportsPage({super.key, this.service});
  final ConnectedChannelSource? service;
  @override
  State<CombatSportsPage> createState() => _CombatSportsPageState();
}

class _CombatSportsPageState extends State<CombatSportsPage> {
  late final service = widget.service ?? ConnectedChannelSource();
  final search = TextEditingController();
  Timer? debounce;
  int page = 0;
  String category = 'all', status = 'all';
  bool opening = false;
  late Future<Map<String, dynamic>> catalog = load();
  Future<Map<String, dynamic>> load() => service.request('combat_catalog', {
        'query': search.text.trim(),
        'page': page,
        'category': category,
        'status': status
      });
  void refresh({bool reset = false}) {
    if (reset) page = 0;
    setState(() {
      catalog = load();
    });
  }

  @override
  void dispose() {
    search.dispose();
    debounce?.cancel();
    super.dispose();
  }

  String timeLabel(dynamic value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    return time == null
        ? 'Time: Unknown'
        : '${DateFormat('dd MMM · h:mm a').format(time.add(const Duration(hours: 6, minutes: 30)))} MMT';
  }

  Future<void> details(Map<String, dynamic> row) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      final response =
          await service.request('combat_details', {'entry_id': row['id']});
      if (!mounted) return;
      final entry = response['entry'] as Map;
      final lines = (entry['lines'] as List? ?? []).whereType<Map>().toList();
      await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (sheet) => ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheet).height * .85),
              child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(entry['name'].toString(),
                        style: Theme.of(sheet).textTheme.titleLarge),
                    const Text(
                        'Source lines only. Video playback has not been verified.'),
                    if (lines.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                              'No native stream lines are published for this event yet.')),
                    for (final line in lines)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(line['label']?.toString() ?? 'Line',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        '${line['source_name']} • ${line['stream_type'].toString().toUpperCase()} • Video not tested'),
                                    SelectableText(
                                        line['stream_url']?.toString() ?? ''),
                                    if ((line['key_id']?.toString() ?? '').isNotEmpty)
                                      SelectableText('Key ID: ${line['key_id']}'),
                                    if ((line['key_data']?.toString() ?? '').isNotEmpty)
                                      SelectableText('Key Data: ${line['key_data']}'),
                                    Wrap(children: [
                                      TextButton.icon(
                                          onPressed: () => Clipboard.setData(
                                              ClipboardData(
                                                  text: line['stream_url']
                                                          ?.toString() ??
                                                      '')),
                                          icon: const Icon(Icons.copy),
                                          label: const Text('Copy URL')),
                                      TextButton.icon(
                                          onPressed: () {
                                            final details = <String>[];
                                            for (final field in const ['label', 'source_name', 'stream_url', 'stream_type', 'referer', 'origin', 'user_agent', 'drm_type', 'license_url', 'key_id', 'key_data']) {
                                              final value = line[field]?.toString() ?? '';
                                              if (value.isNotEmpty) details.add('$field: $value');
                                            }
                                            Clipboard.setData(ClipboardData(text: details.join('\n')));
                                          },
                                          icon: const Icon(Icons.content_copy),
                                          label: const Text('Copy all line details')),
                                      if ((line['key_data']?.toString() ?? '').isEmpty)
                                        TextButton.icon(
                                            onPressed: () => Navigator.of(sheet)
                                                .push(MaterialPageRoute<void>(
                                                    builder: (_) => StreamPreviewPage(
                                                        stream: DetectedStream(
                                                            url: line['stream_url']
                                                                .toString(),
                                                            type:
                                                                line['stream_type']
                                                                    .toString(),
                                                            referer: line['referer']
                                                                    ?.toString() ??
                                                                '',
                                                            origin: line['origin']?.toString() ?? '')))),
                                            icon: const Icon(Icons.play_circle_outline),
                                            label: const Text('Test video')),
                                    ]),
                                    if ((line['key_data']?.toString() ?? '')
                                        .isNotEmpty)
                                      const Text(
                                          'DRM configuration is present; this preview cannot verify that playback.',
                                          style: TextStyle(fontSize: 12)),
                                  ]))),
                  ])));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not load event lines. Refresh and retry.')));
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Combat Sports'), actions: [
          IconButton(
              tooltip: 'Refresh combat events',
              onPressed: () => refresh(),
              icon: const Icon(Icons.refresh))
        ]),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search events, fighters or sources'),
                  onChanged: (_) {
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 350),
                        () => refresh(reset: true));
                  })),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                    child: DropdownButton<String>(
                        isExpanded: true,
                        value: category,
                        items: [
                          for (final entry in const {
                            'all': 'All categories',
                            'ufc': 'UFC',
                            'mma': 'MMA',
                            'boxing': 'Boxing',
                            'one': 'ONE Championship'
                          }.entries)
                            DropdownMenuItem(
                                value: entry.key, child: Text(entry.value))
                        ],
                        onChanged: (value) {
                          category = value ?? 'all';
                          refresh(reset: true);
                        })),
                const SizedBox(width: 12),
                Expanded(
                    child: DropdownButton<String>(
                        isExpanded: true,
                        value: status,
                        items: [
                          for (final value in const [
                            'all',
                            'upcoming',
                            'live',
                            'finished',
                            'unknown'
                          ])
                            DropdownMenuItem(
                                value: value,
                                child: Text(value == 'all'
                                    ? 'All statuses'
                                    : value.toUpperCase()))
                        ],
                        onChanged: (value) {
                          status = value ?? 'all';
                          refresh(reset: true);
                        })),
              ])),
          Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                  future: catalog,
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return Center(
                          child: TextButton(
                              onPressed: () => refresh(),
                              child: const Text(
                                  'Could not load Stream Hub combat events. Retry')));
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final data = snapshot.data!,
                        rows = (data['entries'] as List)
                            .whereType<Map>()
                            .map((x) => Map<String, dynamic>.from(x))
                            .toList(),
                        total = (data['total'] as num?)?.toInt() ?? 0;
                    return Column(children: [
                      if (snapshot.connectionState == ConnectionState.waiting ||
                          opening)
                        const LinearProgressIndicator(),
                      Text(
                          'Stream Hub • ${(data['state'] as Map?)?['status'] ?? 'unknown'} • $total events'),
                      Expanded(
                          child: RefreshIndicator(
                              onRefresh: () async {
                                refresh();
                                await catalog;
                              },
                              child: ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: rows.isEmpty ? 1 : rows.length,
                                  itemBuilder: (context, index) {
                                    if (rows.isEmpty)
                                      return const Padding(
                                          padding: EdgeInsets.all(24),
                                          child: Text(
                                              'No matching combat events are published by the current Stream Hub sources.'));
                                    final row = rows[index];
                                    return Card(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                      '${row['category_name']} • ${row['discipline']} • ${row['status'].toString().toUpperCase()}'),
                                                  Text(
                                                      row['event_name']
                                                          .toString(),
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  Text(row['name'].toString()),
                                                  Text(timeLabel(
                                                      row['kickoff_at'])),
                                                  if (row['kickoff_at'] ==
                                                          null &&
                                                      row['source_time'] !=
                                                          null)
                                                    Text(
                                                        'Source clock (timezone unconfirmed): ${row['source_time']}',
                                                        style: const TextStyle(
                                                            fontSize: 11)),
                                                  Text((row['source_names']
                                                              as List? ??
                                                          [])
                                                      .join(' • ')),
                                                  Row(children: [
                                                    Expanded(
                                                        child: Text(
                                                            '${row['stream_count']} unique lines • Video not tested')),
                                                    TextButton(
                                                        onPressed: opening
                                                            ? null
                                                            : () =>
                                                                details(row),
                                                        child: const Text(
                                                            'VIEW LINES'))
                                                  ]),
                                                ])));
                                  }))),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                onPressed: page == 0
                                    ? null
                                    : () {
                                        page--;
                                        refresh();
                                      },
                                icon: const Icon(Icons.chevron_left)),
                            Text('Page ${page + 1}'),
                            IconButton(
                                onPressed: (page + 1) * 50 >= total
                                    ? null
                                    : () {
                                        page++;
                                        refresh();
                                      },
                                icon: const Icon(Icons.chevron_right))
                          ]),
                    ]);
                  })),
        ]),
      );
}
