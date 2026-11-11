// Enrich missing Big Match badges only with an independently published
// fixture for the SAME teams and near-identical kickoff. No guessed logo URL.
String _teamKey(Object? value) => (value ?? '')
    .toString()
    .toLowerCase()
    .replaceAll('türkiye', 'turkey')
    .replaceAll('turkiye', 'turkey')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

String? verifiedBadgeUrl(Object? value) {
  if (value is! String || value.length > 2048) return null;
  final url = Uri.tryParse(value.trim());
  if (url == null || url.scheme != 'https' || !url.hasAuthority ||
      url.userInfo.isNotEmpty || url.hasPort) return null;
  final host = url.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.internal') || host.endsWith('.local') ||
      host.startsWith('127.') || host.startsWith('10.') ||
      host.startsWith('192.168.') || host.startsWith('169.254.')) return null;
  return url.toString();
}

List<Map<String, dynamic>> mergeVerifiedFootballBadges(
  List<Map<String, dynamic>> fixtures,
  List<dynamic> trustedFixtures,
) {
  return fixtures.map((fixture) {
    final existingHome = verifiedBadgeUrl(fixture['home_logo']);
    final existingAway = verifiedBadgeUrl(fixture['away_logo']);
    if (existingHome != null && existingAway != null) return fixture;
    final kickoff = DateTime.tryParse(
      (fixture['kickoff_at'] ?? '').toString())?.toUtc();
    if (kickoff == null) return fixture;
    final home = _teamKey(fixture['home_name']);
    final away = _teamKey(fixture['away_name']);
    if (home.isEmpty || away.isEmpty) return fixture;
    for (final candidate in trustedFixtures) {
      if (candidate is! Map) continue;
      if (_teamKey(candidate['home_name'] ?? candidate['home_team']) != home ||
          _teamKey(candidate['away_name'] ?? candidate['away_team']) != away) continue;
      final candidateKickoff = DateTime.tryParse(
        (candidate['kickoff_at'] ?? candidate['match_time'] ?? '').toString())?.toUtc();
      if (candidateKickoff == null ||
          kickoff.difference(candidateKickoff).inMinutes.abs() > 120) continue;
      final matchedHome = existingHome ??
          verifiedBadgeUrl(candidate['home_logo'] ?? candidate['home_logo_url']);
      final matchedAway = existingAway ??
          verifiedBadgeUrl(candidate['away_logo'] ?? candidate['away_logo_url']);
      if (matchedHome == null && matchedAway == null) break;
      return {
        ...fixture,
        'home_logo': matchedHome,
        'away_logo': matchedAway,
      };
    }
    return fixture;
  }).toList(growable: false);
}


/// Request only UTC dates actually present in the source. CricHD/Score088TV
/// regularly return matches spanning multiple days even when "All" is used.
/// The old code looked up only the first kickoff, leaving later team badges
/// unavailable. This helper does not change ColaTV's own badge mapping.
List<String> missingBadgeUtcDates(List<Map<String, dynamic>> fixtures,
    {int maxDates = 4}) {
  final dates = <String>{};
  for (final fixture in fixtures) {
    if (verifiedBadgeUrl(fixture['home_logo']) != null &&
        verifiedBadgeUrl(fixture['away_logo']) != null) continue;
    final date = DateTime.tryParse(
      (fixture['kickoff_at'] ?? '').toString(),
    )?.toUtc();
    if (date == null) continue;
    dates.add(
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}',
    );
    if (dates.length >= maxDates) break;
  }
  return dates.toList(growable: false);
}
