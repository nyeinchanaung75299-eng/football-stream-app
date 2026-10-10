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

// NCA shows every public catalog match, even without an imported stream.
// Match identity includes kickoff proximity so fixtures on different days
// cannot accidentally borrow another match's published playback links.
String _ncaTeamKey(dynamic value) =>
    (value ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool ncaSameFixture(Map<String, dynamic> catalog,
    Map<String, dynamic> published) {
  final home = _ncaTeamKey(catalog['home_team']);
  final away = _ncaTeamKey(catalog['away_team']);
  if (home.isEmpty || away.isEmpty ||
      home != _ncaTeamKey(published['home_team']) ||
      away != _ncaTeamKey(published['away_team'])) return false;
  final at = DateTime.tryParse(
      (catalog['match_time'] ?? catalog['kickoff_at'] ?? '').toString());
  final bt = DateTime.tryParse(
      (published['kickoff_at'] ?? '').toString());
  if (at == null || bt == null) return false;
  return at.toUtc().difference(bt.toUtc()).abs() <=
      const Duration(hours: 12);
}

List<Map<String, dynamic>> ncaCatalogWithImportedStreams(
    List<Map<String, dynamic>> catalog,
    List<Map<String, dynamic>> publishedWithNcaLinks) {
  final seen = <String>{};
  final result = <Map<String, dynamic>>[];
  for (final entry in catalog) {
    final sourceId = (entry['source_id'] ?? '').toString().trim();
    final home = (entry['home_team'] ?? '').toString().trim();
    final away = (entry['away_team'] ?? '').toString().trim();
    if (!sourceId.startsWith('match:') || home.isEmpty || away.isEmpty ||
        !seen.add(sourceId)) continue;
    Map<String, dynamic>? imported;
    for (final published in publishedWithNcaLinks) {
      if (ncaSameFixture(entry, published)) {
        imported = published;
        break;
      }
    }
    // The imported entry contains already relabeled NCA lines: trust only
    // their explicitly verified count; no other source is ever copied.
    final safeLinks = imported == null
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            imported['stream_links'] ?? const <Map<String, dynamic>>[]);
    result.add({
      'id': imported?['id'] ?? ('nca:' + sourceId),
      'source_id': sourceId,
      'league': entry['league'] ?? 'Football',
      'home_team': home,
      'away_team': away,
      'kickoff_at': entry['match_time'],
      'is_live': entry['is_live'] == true,
      'stream_count': safeLinks.length,
      'stream_links': safeLinks,
    });
  }
  return result;
}
