import 'package:intl/intl.dart';

/// A fixture's date must have a specified timezone before it can be shown
/// on the Myanmar calendar (UTC + 06:30). Never infer a missing timezone.
DateTime? sourceFixtureMmtKickoff(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (!RegExp(r'(?:Z|[+-]\d{2}:?\d{2})$', caseSensitive: false)
      .hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.toUtc().add(const Duration(hours: 6, minutes: 30));
}

/// Only diagnoses an empty *date or live filter*. Returns null if the source
/// has no usable times, or if the selected filter should have matches.
String? explainEmptyFixtureFilter({
  required String provider,
  required String mode,
  required DateTime selectedDate,
  required List<dynamic> rawMatches,
}) {
  if (mode != 'date' && mode != 'live') return null;
  final eligible = <MapEntry<Map, DateTime>>[];
  for (final raw in rawMatches) {
    if (raw is! Map) continue;
    final home = (raw['home_team'] ?? '').toString().trim();
    final away = (raw['away_team'] ?? '').toString().trim();
    final kickoff = sourceFixtureMmtKickoff(raw['match_time']);
    if (home.isEmpty || away.isEmpty || kickoff == null) continue;
    eligible.add(MapEntry(raw, kickoff));
  }
  if (eligible.isEmpty) return null;
  if (mode == 'live') {
    final live = eligible.any((row) {
      final fixture = row.key;
      return fixture['hot'] == true ||
          fixture['status']?.toString().toUpperCase() == 'LIVE' ||
          fixture['match_status']?.toString().toUpperCase() == 'LIVE';
    });
    if (live) return null;
    return provider + ' returned ' + eligible.length.toString() +
        ' timed football fixtures, but none marked LIVE. '
        'Select All to view the available schedule.';
  }
  final chosen = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
  final dates = eligible.map((entry) =>
      DateTime(entry.value.year, entry.value.month, entry.value.day)).toSet();
  if (dates.contains(chosen)) return null;
  final sortedDates = dates.toList()..sort();
  final labels = sortedDates.take(5).map((date) =>
      DateFormat('dd MMM yyyy', 'en_US').format(date)).join(', ');
  final more = sortedDates.length > 5 ? ', +' +
      (sortedDates.length - 5).toString() + ' more dates' : '';
  return provider + ' returned ' + eligible.length.toString() +
      ' timed football fixtures, but none on ' +
      DateFormat('dd MMM yyyy', 'en_US').format(chosen) + ' Myanmar Time. '
      'Available MMT dates: ' + labels + more +
      '. Choose All or select one of those dates.';
}
