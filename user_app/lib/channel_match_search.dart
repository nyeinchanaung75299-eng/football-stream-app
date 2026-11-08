String _words(Object? value) => (value ?? '').toString().toLowerCase()
    .replaceAllMapped(RegExp(r'([a-z])([0-9])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String programmeSearchText(Map programme) =>
    '${programme['title'] ?? ''} ${programme['subtitle'] ?? ''} ${programme['description'] ?? ''}';

bool currentFootballProgramme(Map programme, {DateTime? now}) {
  if (programme['stream_ambiguous'] == true) return false;
  final body = _words(programmeSearchText(programme));
  if (RegExp(r'\b(replay|highlights?|recap|preview|repeat|classic|magazine|review|aflw?|australian rules|aussie rules|american football|nfl|nba|hockey|rugby|cricket|tennis|basketball|motorsport|esports|formula 1)\b').hasMatch(body)) return false;
  final versus = RegExp(r'\b(vs|v|versus)\b').hasMatch(body);
  final hosted = RegExp(r'\blive\b').hasMatch(body) &&
      RegExp(r'\b(soccer|premier league|la liga|bundesliga|serie a|ligue 1|champions league)\b').hasMatch(body) &&
      RegExp(r'\b(host|hosts|hosting|face|faces|take on|takes on)\b').hasMatch(body);
  final labelledFixture = RegExp(r'\b(soccer|football|serie a|premier league|la liga|bundesliga|ligue 1|champions league)\b').hasMatch(body) &&
      RegExp(r'\w\s*[-–—]\s*\w').hasMatch(programmeSearchText(programme));
  if (!versus && !hosted && !labelledFixture) return false;
  final startMs = programme['start'];
  if (startMs is! num) return false;
  final start = DateTime.fromMillisecondsSinceEpoch(startMs.toInt(), isUtc: true);
  final endMs = programme['end'];
  final end = endMs is num ? DateTime.fromMillisecondsSinceEpoch(endMs.toInt(), isUtc: true) : start.add(const Duration(hours: 3));
  final current = (now ?? DateTime.now()).toUtc();
  return end.isAfter(current) && !start.isAfter(current.add(const Duration(days: 8)));
}

List<String> _aliases(Object? team) {
  final name = _words(team);
  final short = name.replaceFirst(RegExp(r'^(?:ssc|acf|afc|fc|ac|sc|cf|cd|rc) '), '')
      .replaceFirst(RegExp(r' (?:fc|afc|cf|sc|football club)$'), '');
  const known = <String, List<String>>{
    'tottenham hotspur': ['tottenham', 'spurs'], 'ssc napoli': ['napoli', 'naples'],
    'napoli': ['naples'], 'manchester city': ['man city'],
    'manchester united': ['man united', 'man utd'],
    'inter milan': ['inter'], 'inter': ['inter milan'], 'ac milan': ['milan'],
    'newcastle united': ['newcastle'], 'athletic club': ['athletic bilbao'],
  };
  return {name, short, ...?known[name]}.where((s) => s.length >= 3).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

bool programmeCoversMatch(Map programme, Map match, {DateTime? now}) {
  if (!currentFootballProgramme(programme, now: now)) return false;
  final kickoff = DateTime.tryParse('${match['kickoff_at'] ?? ''}');
  if (kickoff == null) return false;
  final start = DateTime.fromMillisecondsSinceEpoch((programme['start'] as num).toInt(), isUtc: true);
  final gap = start.difference(kickoff.toUtc()).inMinutes;
  if (gap < -90 || gap > 75) return false;
  final body = ' ${_words(programmeSearchText(programme))} ';
  // Mask the longest home-team name before finding the away team, so the
  // word Milan inside Inter Milan cannot also satisfy AC Milan.
  for (final home in _aliases(match['home_team'])) {
    final needle = ' $home ';
    final index = body.indexOf(needle);
    if (index < 0) continue;
    final remaining = body.replaceRange(index, index + needle.length, ' ');
    return _aliases(match['away_team']).any((away) => remaining.contains(' $away '));
  }
  return false;
}

bool channelMatchesProgrammeQuery(Map channel, List<Map<String, dynamic>> programmes, String query) {
  final expanded = query.toLowerCase().replaceAll(RegExp(r'\bspurs\b|စပါး'), 'tottenham');
  final terms = _words(expanded).split(' ').where((s) => s.isNotEmpty).toList();
  if (terms.isEmpty) return true;
  final metadata = _words('${channel['name'] ?? ''} ${channel['category'] ?? ''}');
  bool matches(String text) => terms.every(text.contains);
  return matches(metadata) || programmes.any((p) => matches('$metadata ${_words(programmeSearchText(p))}'));
}
