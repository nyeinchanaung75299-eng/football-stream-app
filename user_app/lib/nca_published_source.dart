// Explicit provenance from the Admin stream import, not Live match counts.
bool isNcaPublishedLine(Map<String, dynamic> line) {
  final label = (line['label'] ?? '').toString().trim();
  return RegExp(r'^TFLIX\s*•\s*', caseSensitive: false).hasMatch(label);
}

String ncaDisplayLabel(Map<String, dynamic> line) {
  final raw = (line['label'] ?? '').toString();
  final server =
      RegExp(r'\bServer\s*(\d+)\b', caseSensitive: false).firstMatch(raw);
  if (server != null) return 'NCA Server ' + server.group(1)!;
  final format = (line['stream_type'] ?? '').toString().toUpperCase();
  return format.isEmpty ? 'NCA Stream' : 'NCA • ' + format;
}

List<Map<String, dynamic>> ncaPublishedLines(
    List<Map<String, dynamic>> lines) {
  final ids = <String>{};
  final results = <Map<String, dynamic>>[];
  for (final line in lines) {
    if (!isNcaPublishedLine(line)) continue;
    final url = (line['stream_url'] ?? '').toString().trim();
    final id = (line['id'] ?? '').toString().trim();
    final key = id.isNotEmpty ? id : url;
    if (key.isEmpty || !ids.add(key)) continue;
    results.add({...line, 'label': ncaDisplayLabel(line)});
  }
  return results;
}
