typedef SourceMatch = Map<String, dynamic>;

DateTime? sourceMatchKickoff(SourceMatch match) =>
    DateTime.tryParse(match['match_time']?.toString() ?? '');

List<SourceMatch> sourceMatchAnchors(SourceMatch match, String source) {
  final raw = match['anchors'];
  if (raw is List) {
    final anchors = raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where(
          (row) =>
              (row['room_num']?.toString().trim().isNotEmpty ?? false) ||
              (row['page_url']?.toString().trim().isNotEmpty ?? false),
        )
        .toList();
    if (anchors.isNotEmpty) return anchors;
  }
  // Soco/YYZB schedule IDs identify fixtures, not streamer rooms.
  if (source == 'soco' || source == 'yyzb' || source == 'arena') return const [];
  final room = (match['source_id'] ?? match['schedule_id'] ?? '')
      .toString()
      .trim();
  final page = match['page_url']?.toString().trim() ?? '';
  if (room.isEmpty && page.isEmpty) return const [];
  return [
    {'room_num': room, 'page_url': page},
  ];
}

int compareSourceMatches(
  SourceMatch a,
  SourceMatch b, {
  required bool Function(SourceMatch) isLive,
}) {
  if (a['source'] == 'totalsportek' && b['source'] == 'totalsportek') {
    final aLive = isLive(a), bLive = isLive(b);
    if (aLive != bLive) return aLive ? -1 : 1;
    // These are published countdowns, used only for ordering. They must not
    // be turned into invented kickoff timestamps.
    final ac = a['countdown_minutes'], bc = b['countdown_minutes'];
    if (ac is num && bc is num && ac != bc) return ac.compareTo(bc);
    if (ac is num && bc is! num) return -1;
    if (bc is num && ac is! num) return 1;
  }
  // Always use kickoff time first. Hot/live flags do not belong ahead of
  // earlier matches; otherwise a 02:30 hot fixture jumps above 00:30 fixtures.
  final at = sourceMatchKickoff(a), bt = sourceMatchKickoff(b);
  if (at != null && bt != null) {
    final time = at.compareTo(bt);
    if (time != 0) return time;
  } else if (at != null) {
    return -1;
  } else if (bt != null) {
    return 1;
  }
  // Only break a same-time tie with genuine live status and featured flags.
  final aLive = isLive(a), bLive = isLive(b);
  if (aLive != bLive) return aLive ? -1 : 1;
  final aHot = a['hot'] == true, bHot = b['hot'] == true;
  if (aHot != bHot) return aHot ? -1 : 1;
  // Stable tie-breaking keeps simultaneous kickoffs from moving on refresh.
  return (a['source_id'] ?? a['schedule_id'] ?? a['home_team'] ?? '')
      .toString()
      .compareTo(
        (b['source_id'] ?? b['schedule_id'] ?? b['home_team'] ?? '').toString(),
      );
}

List<SourceMatch> filterSourceMatches(
  List<SourceMatch> matches, {
  required bool todayOnly,
  bool streamsOnly = false,
  String source = 'soco',
  String query = '',
  String? league,
  DateTime? now,
}) {
  final today = (now ?? DateTime.now()).toLocal();
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return matches.where((match) {
    // Apply the room policy to older local/mirror catalogs as well as fresh
    // API data. A fixture ID is never evidence that a stream room exists.
    if (source == 'yyzb' &&
        sourceMatchAnchors(match, source).isEmpty) return false;
    if (streamsOnly && sourceMatchAnchors(match, source).isEmpty) return false;
    if (todayOnly) {
      final kickoff = sourceMatchKickoff(match)?.toLocal();
      if (kickoff == null ||
          kickoff.year != today.year ||
          kickoff.month != today.month ||
          kickoff.day != today.day)
        return false;
    }
    if (league != null && match['league']?.toString() != league) return false;
    final text = [
      match['league'],
      match['home_team'],
      match['away_team'],
      if ([match['home_team'], match['away_team']].any(
        (name) => name?.toString().toLowerCase().contains('tottenham') ?? false,
      )) 'Spurs စပါး',
    ].whereType<String>().join(' ').toLowerCase();
    return terms.every(text.contains);
  }).toList();
}

List<String> sourceMatchLeagues(List<SourceMatch> matches) {
  final leagues = matches
      .map((match) => match['league']?.toString().trim() ?? '')
      .where((league) => league.isNotEmpty)
      .toSet()
      .toList();
  leagues.sort((a, b) {
    bool premier(String value) => const {
      'english premier league',
      'premier league',
    }.contains(value.toLowerCase());
    final aPremier = premier(a);
    final bPremier = premier(b);
    if (aPremier != bPremier) return aPremier ? -1 : 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return leagues;
}
