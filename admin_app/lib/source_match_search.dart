bool sourceMatchMatchesQuery(Map<String, dynamic> match, String query) {
  final teams = [match['home_team'], 'vs', match['away_team']]
      .whereType<String>().join(' ').toLowerCase();
  final text = [match['league'], teams,
    if (teams.contains('tottenham')) 'Spurs စပါး',
  ].whereType<String>().join(' ').toLowerCase();
  return query.trim().toLowerCase().split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty).every(text.contains);
}

int compareAdminSourceMatches(Map<String, dynamic> a,
    Map<String, dynamic> b, String source) {
  if (source == 'totalsportek') {
    bool live(Map<String, dynamic> row) => row['is_live'] == true ||
        row['status']?.toString().toUpperCase() == 'LIVE';
    if (live(a) != live(b)) return live(a) ? -1 : 1;
    num countdown(Map<String, dynamic> row) {
      final value = row['countdown_minutes'];
      return value is num && value.isFinite && value >= 0
          ? value : double.infinity;
    }
    final byCountdown = countdown(a).compareTo(countdown(b));
    if (byCountdown != 0) return byCountdown;
    // Metadata arrives a few rows at a time. Sorting known times ahead of
    // unknown times would bury untouched fixtures below later matches.
  } else {
    final at = DateTime.tryParse(a['match_time']?.toString() ?? '') ?? DateTime(9999);
    final bt = DateTime.tryParse(b['match_time']?.toString() ?? '') ?? DateTime(9999);
    final byTime = at.compareTo(bt);
    if (byTime != 0) return byTime;
  }
  final byHome = (a['home_team'] ?? '').toString().toLowerCase()
      .compareTo((b['home_team'] ?? '').toString().toLowerCase());
  if (byHome != 0) return byHome;
  return (a['source_id'] ?? a['schedule_id'] ?? '').toString()
      .compareTo((b['source_id'] ?? b['schedule_id'] ?? '').toString());
}
