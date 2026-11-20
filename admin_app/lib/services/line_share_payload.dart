/// Export only the fields already available in the Admin copy menu. Never
/// serialize entire API rows (which may include unrelated account metadata).
class LineSharePayload {
  LineSharePayload(this.matchName, Iterable<Map> rows)
      : lines = rows
            .map((row) => Map<String, String>.fromEntries([
                  for (final key in const [
                    'label',
                    'stream_type',
                    'stream_url',
                    'referer',
                    'origin',
                    'key_id',
                    'key_data'
                  ])
                    if (row[key]?.toString().trim().isNotEmpty == true)
                      MapEntry(key, row[key].toString().trim()),
                ]))
            .toList();

  final String matchName;
  final List<Map<String, String>> lines;

  static String details(Map line) => [
        'URL: ${line['stream_url'] ?? ''}',
        for (final pair in const {
          'referer': 'Referer',
          'origin': 'Origin',
          'key_id': 'Key ID',
          'key_data': 'Key Data'
        }.entries)
          if (line[pair.key]?.toString().isNotEmpty == true)
            '${pair.value}: ${line[pair.key]}',
      ].join('\n');

  String get text => [
        matchName,
        for (var i = 0; i < lines.length; i++) ...[
          '',
          '${i + 1}. ${lines[i]['label'] ?? 'Line'}',
          if (lines[i]['stream_type'] != null)
            'Type: ${lines[i]['stream_type']!.toUpperCase()}',
          details(lines[i]),
        ],
      ].join('\n');

  // Avoid oversized browser/deep-link URLs. Large exports use a text file
  // through the system share sheet instead of silently truncating any line.
  Uri? get telegramUri {
    final first =
        lines.isEmpty ? null : Uri.tryParse(lines.first['stream_url'] ?? '');
    if (first == null ||
        !const {'https', 'http'}.contains(first.scheme) ||
        first.host.isEmpty ||
        first.userInfo.isNotEmpty) return null;
    final body =
        text.replaceFirst('URL: $first\n', '').replaceFirst('URL: $first', '');
    final uri = Uri.https(
        't.me', '/share/url', {'url': first.toString(), 'text': body});
    return uri.toString().length <= 7000 && text.length <= 3500 ? uri : null;
  }

  String get filename {
    final name = matchName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return '${name.isEmpty ? 'match' : name.substring(0, name.length.clamp(0, 80))}-lines.txt';
  }
}
