import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SourceQualitySheet extends StatefulWidget {
  const SourceQualitySheet(
      {super.key,
      required this.title,
      required this.lines,
      required this.onAdd,
      required this.onRefresh,
      required this.onTest,
      required this.onOpenMatch});
  final String title;
  final List<Map<String, dynamic>> lines;
  final Future<Map<String, dynamic>?> Function(List<Map<String, dynamic>>)
      onAdd;
  final VoidCallback onRefresh;
  final Future<void> Function(Map<String, dynamic>) onTest;
  final void Function(String) onOpenMatch;
  @override
  State<SourceQualitySheet> createState() => _SourceQualitySheetState();
}

class _SourceQualitySheetState extends State<SourceQualitySheet> {
  final selected = <int>{}, added = <int>{};
  bool working = false;
  final testing = <int>{};
  String? message, matchId;
  Future<void> add(List<int> indices) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      final result =
          await widget.onAdd([for (final i in indices) widget.lines[i]]);
      if (!mounted || result == null) return;
      setState(() {
        added.addAll(indices);
        selected.removeAll(indices);
        matchId = result['match_id']?.toString();
        message = 'Added ✓ • ${indices.length} line(s)';
      });
    } catch (_) {
      if (mounted)
        setState(() => message =
            'Save was not confirmed. Your selection is kept. Retry uses the same request.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> copy(Map<String, dynamic> line, {bool details = false}) async {
    final text = details
        ? [
            'URL: ${line['url']}',
            for (final key in [
              'stream_type',
              'resolution',
              'referer',
              'origin',
              'key_id',
              'key_data'
            ])
              if ('${line[key] ?? ''}'.isNotEmpty) '$key: ${line[key]}'
          ].join('\n')
        : '${line['url']}';
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted)
        setState(
            () => message = details ? 'Details copied ✓' : 'Link copied ✓');
    } catch (_) {
      if (mounted)
        setState(
            () => message = 'Copy failed. Open Details to select the link.');
    }
  }

  void details(Map<String, dynamic> line) => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: const Text('Line details'),
              content: SingleChildScrollView(
                  child: SelectableText([
                '${line['url']}',
                for (final key in [
                  'stream_type',
                  'resolution',
                  'referer',
                  'origin',
                  'key_id',
                  'key_data'
                ])
                  if ('${line[key] ?? ''}'.isNotEmpty) '$key: ${line[key]}',
                'Playlist: ${line['media_verified'] == true ? 'checked' : 'not verified'}',
                'Video: not verified on this device',
              ].join('\n'))),
              actions: [
                TextButton(
                    onPressed: () => copy(line, details: true),
                    child: const Text('Copy details')),
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Close'))
              ]));
  @override
  Widget build(BuildContext context) => SafeArea(
      child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .88),
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Select Stream Quality',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(widget.title),
                    const SizedBox(height: 8),
                    const Text('Choose lines, then confirm the NCA match.',
                        style: TextStyle(fontSize: 12)),
                    Wrap(spacing: 8, children: [
                      TextButton(
                          onPressed: working
                              ? null
                              : () => setState(() {
                                    selected.clear();
                                    selected.addAll(List.generate(
                                        widget.lines.length, (i) => i));
                                  }),
                          child: const Text('Select all')),
                      TextButton.icon(
                          onPressed: working ? null : widget.onRefresh,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh links'))
                    ]),
                    if (working) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(message!)),
                    for (var i = 0; i < widget.lines.length; i++)
                      Builder(builder: (context) {
                        final line = widget.lines[i];
                        return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(children: [
                                  Row(children: [
                                    Checkbox(
                                        value: selected.contains(i),
                                        onChanged: working
                                            ? null
                                            : (value) => setState(() {
                                                  value == true
                                                      ? selected.add(i)
                                                      : selected.remove(i);
                                                })),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              '${line['label'] ?? 'Stream'} • ${line['stream_type'] ?? 'auto'}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                          Text('${line['url']}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                          for (final field in [
                                            'resolution',
                                            'referer',
                                            'origin'
                                          ])
                                            if ('${line[field] ?? ''}'
                                                .isNotEmpty)
                                              Text('$field: ${line[field]}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                          Text(
                                              added.contains(i)
                                                  ? 'ADDED ✓'
                                                  : '${line['health_status'] ?? 'unknown'} • Video not verified',
                                              style: const TextStyle(
                                                  fontSize: 11)),
                                        ])),
                                  ]),
                                  Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        IconButton(
                                            tooltip: 'Copy video URL',
                                            onPressed: () => copy(line),
                                            icon:
                                                const Icon(Icons.copy_rounded)),
                                        FilledButton(
                                            onPressed:
                                                working ? null : () => add([i]),
                                            child: Text(added.contains(i)
                                                ? 'UPDATE'
                                                : 'ADD')),
                                        TextButton(
                                            onPressed: () => details(line),
                                            child: const Text('Details')),
                                        TextButton(
                                            onPressed: working ||
                                                    testing.contains(i)
                                                ? null
                                                : () async {
                                                    setState(
                                                        () => testing.add(i));
                                                    try {
                                                      await widget.onTest(line);
                                                    } catch (_) {
                                                      if (mounted)
                                                        setState(() => message =
                                                            'Could not open this video. Retry or refresh links.');
                                                    } finally {
                                                      if (mounted)
                                                        setState(() =>
                                                            testing.remove(i));
                                                    }
                                                  },
                                            child: const Text('Test video'))
                                      ]),
                                ])));
                      }),
                    if (selected.isNotEmpty)
                      FilledButton.icon(
                          onPressed: working
                              ? null
                              : () => add(selected.toList()..sort()),
                          icon: const Icon(Icons.playlist_add),
                          label: Text('ADD SELECTED (${selected.length})')),
                    if (matchId != null)
                      OutlinedButton.icon(
                          onPressed: working
                              ? null
                              : () => widget.onOpenMatch(matchId!),
                          icon: const Icon(Icons.edit),
                          label: const Text('Open match in Controls')),
                    TextButton(
                        onPressed:
                            working ? null : () => Navigator.pop(context),
                        child: const Text('Close')),
                  ]))));
}
