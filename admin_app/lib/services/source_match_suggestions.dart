import '../football_english.dart';

String _team(String value) => englishKnownFootballName(value)
    .toLowerCase()
    .replaceAll(RegExp(r'\b(fc|cf)\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9]'), '')
    .replaceAll('manutd', 'manchesterunited')
    .replaceAll('bayernmunchen', 'bayernmunich')
    .replaceAll('spurs', 'tottenhamhotspur');
int destinationScore(Map<String, dynamic> source, Map<String, dynamic> target) {
  final sh = _team('${source['home_team'] ?? ''}'),
      sa = _team('${source['away_team'] ?? ''}');
  final th = _team('${target['home_team'] ?? ''}'),
      ta = _team('${target['away_team'] ?? ''}');
  if (sh.isEmpty || sa.isEmpty || sh != th || sa != ta) return 0;
  final st = DateTime.tryParse('${source['match_time'] ?? ''}'),
      tt = DateTime.tryParse('${target['kickoff_at'] ?? ''}');
  if (st != null && tt != null) {
    final gap = st.difference(tt).inMinutes.abs();
    if (gap > 120) return 0;
    return 300 - gap;
  }
  return 100; // Team-only suggestion still requires explicit confirmation.
}

List<Map<String, dynamic>> suggestDestinations(
    List<Map<String, dynamic>> rows, Map<String, dynamic>? source,
    {String? preferred}) {
  final result = [...rows];
  result.sort((a, b) {
    final byScore = source == null
        ? 0
        : destinationScore(source, b).compareTo(destinationScore(source, a));
    if (byScore != 0) return byScore;
    final ap = a['id'] == preferred, bp = b['id'] == preferred;
    if (ap != bp) return ap ? -1 : 1;
    return '${a['kickoff_at'] ?? ''}'.compareTo('${b['kickoff_at'] ?? ''}');
  });
  return result;
}
