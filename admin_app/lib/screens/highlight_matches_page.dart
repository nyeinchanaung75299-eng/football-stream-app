import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get _client => Supabase.instance.client;

String _title(Map row) => "${row['home_team']} vs ${row['away_team']}";

Future<String?> chooseHighlightMatch(
    BuildContext context, List<Map<String, dynamic>> matches) async {
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Add highlight to'),
      children: [
        for (final match in matches)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, match['id'].toString()),
            child: ListTile(
              title: Text(_title(match)),
              subtitle:
                  Text("${match['league']} • ${match['kickoff_at'] ?? ''}"),
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, ''),
          child: const Text('Save as a standalone highlight'),
        ),
      ],
    ),
  );
}

class HighlightMatchesPage extends StatefulWidget {
  const HighlightMatchesPage({super.key});

  @override
  State<HighlightMatchesPage> createState() => _HighlightMatchesPageState();
}

class _HighlightMatchesPageState extends State<HighlightMatchesPage> {
  static const pageSize = 30;
  int offset = 0;
  late Future<PostgrestList> matches = _load();

  Future<PostgrestList> _load() async => await _client
      .from('highlight_matches')
      .select('*,highlights(id,title,video_url,stream_type)')
      .order('kickoff_at', ascending: false)
      .order('id')
      .range(offset, offset + pageSize - 1);

  void _refresh() => setState(() => matches = _load());

  Future<void> _write(Future<void> Function() write) async {
    try {
      await write();
      if (mounted) _refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to save changes. Please retry.')),
        );
    }
  }

  Future<void> _editMatch(Map row) async {
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditHighlightMatch(row: row),
    );
    if (!mounted || changes == null) return;
    await _write(() async {
      await _client
          .from('highlight_matches')
          .update(changes)
          .eq('id', row['id']);
    });
  }

  Future<void> _line(Map match, [Map? line]) async {
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditHighlightLine(row: line),
    );
    if (!mounted || changes == null) return;
    await _write(() async {
      if (line == null) {
        await _client.from('highlights').insert({
          ...changes,
          'match_id': match['id'],
          'is_active': true,
        });
      } else {
        await _client.from('highlights').update(changes).eq('id', line['id']);
      }
    });
  }

  Future<void> _delete(String table, String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _write(() async {
      await _client.from(table).delete().eq('id', id);
    });
  }

  Widget _logo(dynamic url) => SizedBox(
        width: 40,
        height: 40,
        child: url == null || url.toString().isEmpty
            ? const Icon(Icons.shield_outlined)
            : Image.network(url.toString(),
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.shield_outlined)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HL Edit & Delete')),
        body: FutureBuilder<PostgrestList>(
          future: matches,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                child: TextButton(
                    onPressed: _refresh,
                    child: const Text('Could not load highlights. Retry')),
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (rows.isEmpty) const Text('No matches on this page.'),
                for (final row in rows)
                  Card(
                      child: Column(
                    children: [
                      ListTile(
                        leading: _logo(row['home_logo_url']),
                        title: Text(_title(row)),
                        subtitle: Text(
                            "${row['league']} • ${row['home_score'] == null ? 'No score' : "${row['home_score']}–${row['away_score']}"}${row['is_finished'] == true ? ' • FT' : ''}"),
                        trailing: _logo(row['away_logo_url']),
                      ),
                      Wrap(children: [
                        TextButton.icon(
                            onPressed: () => _editMatch(row),
                            icon: const Icon(Icons.edit),
                            label: const Text('Edit match')),
                        TextButton.icon(
                            onPressed: () => _delete(
                                'highlight_matches',
                                row['id'].toString(),
                                'Delete this HL match and its highlight lines?'),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete match')),
                      ]),
                      for (final line
                          in (row['highlights'] as List).whereType<Map>())
                        ListTile(
                          title: Text(line['title'].toString()),
                          subtitle: Text(
                              line['stream_type'].toString().toUpperCase()),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Edit line',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _line(row, line)),
                            IconButton(
                                tooltip: 'Delete line',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(
                                    'highlights',
                                    line['id'].toString(),
                                    'Delete this highlight line?')),
                          ]),
                        ),
                      TextButton.icon(
                          onPressed: () => _line(row),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Highlight Line')),
                    ],
                  )),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: offset == 0
                            ? null
                            : () {
                                offset -= pageSize;
                                _refresh();
                              },
                        child: const Text('Previous'),
                      ),
                      TextButton(
                        onPressed: rows.length < pageSize
                            ? null
                            : () {
                                offset += pageSize;
                                _refresh();
                              },
                        child: const Text('Next'),
                      ),
                    ]),
              ],
            );
          },
        ),
      );
}

class _EditHighlightMatch extends StatefulWidget {
  const _EditHighlightMatch({required this.row});
  final Map row;

  @override
  State<_EditHighlightMatch> createState() => _EditHighlightMatchState();
}

class _EditHighlightMatchState extends State<_EditHighlightMatch> {
  final form = GlobalKey<FormState>();
  static const labels = {
    'league': 'League',
    'home_team': 'Home team',
    'away_team': 'Away team',
    'home_logo_url': 'Home logo URL',
    'away_logo_url': 'Away logo URL',
    'home_score': 'Home score',
    'away_score': 'Away score',
  };
  late final fields = {
    for (final key in labels.keys)
      key: TextEditingController(text: widget.row[key]?.toString() ?? ''),
  };
  late bool finished = widget.row['is_finished'] == true;

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String? _validate(String key, String value) {
    if (key.endsWith('_score')) {
      final peer = key == 'home_score' ? 'away_score' : 'home_score';
      if (value.isEmpty && fields[peer]!.text.trim().isEmpty) return null;
      final score = int.tryParse(value);
      return score == null || score < 0 || score > 2147483647
          ? 'Enter both scores as non-negative integers'
          : null;
    }
    if (key.endsWith('_url'))
      return value.isEmpty || _validUrl(value) ? null : 'Enter an HTTP(S) URL';
    return value.isEmpty ? 'Required' : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit HL match'),
        content: SingleChildScrollView(
            child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final field in labels.entries)
              TextFormField(
                controller: fields[field.key],
                keyboardType: field.key.endsWith('_score')
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(labelText: field.value),
                validator: (value) =>
                    _validate(field.key, (value ?? '').trim()),
              ),
            CheckboxListTile(
                title: const Text('Full time (FT)'),
                value: finished,
                onChanged: (value) => setState(() => finished = value == true)),
          ]),
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                Navigator.pop(context, <String, dynamic>{
                  for (final entry in fields.entries)
                    entry.key: entry.key.endsWith('_score')
                        ? int.tryParse(entry.value.text.trim())
                        : entry.value.text.trim().isEmpty
                            ? null
                            : entry.value.text.trim(),
                  'is_finished': finished,
                });
              },
              child: const Text('Save')),
        ],
      );
}

bool _validUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class _EditHighlightLine extends StatefulWidget {
  const _EditHighlightLine({this.row});
  final Map? row;
  @override
  State<_EditHighlightLine> createState() => _EditHighlightLineState();
}

class _EditHighlightLineState extends State<_EditHighlightLine> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
      text: widget.row?['title']?.toString() ?? 'Highlights');
  late final url =
      TextEditingController(text: widget.row?['video_url']?.toString());
  late String type = widget.row?['stream_type']?.toString() ?? 'auto';

  @override
  void dispose() {
    title.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.row == null ? 'Add Highlight Line' : 'Edit Highlight Line'),
        content: SingleChildScrollView(
            child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Label'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Required' : null),
            TextFormField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Video URL'),
                keyboardType: TextInputType.url,
                validator: (value) => _validUrl((value ?? '').trim())
                    ? null
                    : 'Enter an HTTP(S) URL'),
            DropdownButtonFormField<String>(
              initialValue: type,
              items: [
                for (final value in ['auto', 'hls', 'dash', 'mp4'])
                  DropdownMenuItem(
                      value: value, child: Text(value.toUpperCase()))
              ],
              onChanged: (value) {
                if (value != null) type = value;
              },
            ),
          ]),
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate())
                  Navigator.pop(context, <String, dynamic>{
                    'title': title.text.trim(),
                    'video_url': url.text.trim(),
                    'stream_type': type,
                  });
              },
              child: const Text('Save')),
        ],
      );
}
