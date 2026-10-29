import 'dart:convert';

import 'package:http/http.dart' as http;

import '../network_endpoints.dart';

/// Public programme metadata for a channel in the Admin catalog.
///
/// This model intentionally has no stream URL, playback token or DRM field.
class TvScheduleProgramme {
  const TvScheduleProgramme({
    required this.start,
    required this.end,
    required this.title,
    required this.subtitle,
    required this.description,
  });

  final DateTime start;
  final DateTime? end;
  final String title;
  final String subtitle;
  final String description;

  factory TvScheduleProgramme.fromJson(Map<String, dynamic> json) {
    final start = _milliseconds(json['start']);
    if (start == null) {
      throw const FormatException('Schedule programme has no start time.');
    }
    return TvScheduleProgramme(
      start: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
      end: _milliseconds(json['end']) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              _milliseconds(json['end'])!,
              isUtc: true,
            ),
      title: _text(json['title']),
      subtitle: _text(json['subtitle']),
      description: _text(json['description']),
    );
  }
}

/// One of the Admin's saved TV channels plus its public guide entries.
class TvScheduleChannel {
  const TvScheduleChannel({
    required this.id,
    required this.name,
    required this.category,
    required this.hasGuide,
    required this.region,
    required this.programmes,
  });

  final String id;
  final String name;
  final String category;
  final bool hasGuide;
  final String region;
  final List<TvScheduleProgramme> programmes;

  factory TvScheduleChannel.fromJson(Map<String, dynamic> json) {
    final rows = json['programmes'];
    return TvScheduleChannel(
      id: _text(json['id']),
      name: _text(json['name']),
      category: _text(json['category']),
      hasGuide: json['matchedEPG'] == true,
      region: _text(json['region']),
      programmes: rows is List
          ? rows
              .whereType<Map>()
              .map((row) => TvScheduleProgramme.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

class TvScheduleAiring {
  const TvScheduleAiring({
    required this.channel,
    required this.when,
    required this.title,
    required this.region,
  });

  final String channel;
  final DateTime when;
  final String title;
  final String region;
}

class TvScheduleGuide {
  const TvScheduleGuide({
    required this.timezone,
    required this.updatedAt,
    required this.channels,
  });

  final String timezone;
  final DateTime? updatedAt;
  final List<TvScheduleChannel> channels;

  factory TvScheduleGuide.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    return TvScheduleGuide(
      timezone: _text(json['timezone']).isEmpty
          ? 'Asia/Yangon'
          : _text(json['timezone']),
      updatedAt: DateTime.tryParse(_text(json['updated_at']))?.toUtc(),
      channels: rawChannels is List
          ? rawChannels
              .whereType<Map>()
              .map((row) => TvScheduleChannel.fromJson(
                    Map<String, dynamic>.from(row),
                  ))
              .where((channel) => channel.id.isNotEmpty && channel.name.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  /// Finds live, non-replay guide entries near a match kickoff. Matching is
  /// deliberately conservative: a channel is shown only when both teams are
  /// present in the guide entry and its time is close to kickoff.
  List<TvScheduleAiring> airingsForMatch(Map<String, dynamic> match) {
    final kickoff = DateTime.tryParse(_text(match['kickoff_at']))?.toUtc();
    if (kickoff == null) return const [];

    final home = _teamAliases(_text(match['home_team']));
    final away = _teamAliases(_text(match['away_team']));
    if (home.isEmpty || away.isEmpty) return const [];

    final airings = <TvScheduleAiring>[];
    for (final channel in channels) {
      if (!channel.hasGuide) continue;
      TvScheduleProgramme? best;
      for (final programme in channel.programmes) {
        final gap = programme.start.difference(kickoff).inMinutes;
        if (gap < -90 || gap > 75) continue;
        final body = _normalise(
          '${programme.title} ${programme.subtitle} ${programme.description}',
        );
        if (body.isEmpty || _isReplay(body)) continue;
        if (!_containsAlias(body, home) || !_containsAlias(body, away)) {
          continue;
        }
        if (best == null ||
            programme.start.difference(kickoff).abs() <
                best.start.difference(kickoff).abs()) {
          best = programme;
        }
      }
      if (best != null) {
        airings.add(
          TvScheduleAiring(
            channel: channel.name,
            when: best.start,
            title: best.title,
            region: channel.region,
          ),
        );
      }
    }
    airings.sort((a, b) {
      final byTime = a.when.compareTo(b.when);
      return byTime != 0 ? byTime : a.channel.compareTo(b.channel);
    });
    return airings;
  }
}

/// Reads schedule metadata through NCA's public Worker. The Worker filters the
/// upstream payload, adds CORS for Admin Web, and never relays playback data.
class TvScheduleService {
  TvScheduleService({http.Client? httpClient, List<String>? apiBases})
      : _httpClient = httpClient,
        _apiBases = apiBases;

  final http.Client? _httpClient;
  final List<String>? _apiBases;

  Future<TvScheduleGuide> load({DateTime? now}) async {
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final date = _yangonDate(now ?? DateTime.now());
      // Use the configured custom domain first. The workers.dev hostname can
      // serve an older deployment while the production route is updated.
      final bases = _apiBases ?? publicApiBases();
      for (final rawBase in bases.toSet()) {
        final base = rawBase.trim().replaceAll(RegExp(r'/+$'), '');
        if (base.isEmpty) continue;
        try {
          final uri = Uri.parse('$base/tv-schedule').replace(
            queryParameters: {'date': date, 'days': '8'},
          );
          final response = await client
              .get(uri, headers: const {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 10));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw StateError('TV schedule returned HTTP ${response.statusCode}.');
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map) {
            throw const FormatException('Invalid TV schedule response.');
          }
          return TvScheduleGuide.fromJson(Map<String, dynamic>.from(decoded));
        } catch (_) {}
      }
      throw StateError('TV schedule is unavailable.');
    } finally {
      if (ownsClient) client.close();
    }
  }
}

int? _milliseconds(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _yangonDate(DateTime value) {
  final yangon = value.toUtc().add(const Duration(hours: 6, minutes: 30));
  final month = yangon.month.toString().padLeft(2, '0');
  final day = yangon.day.toString().padLeft(2, '0');
  return '${yangon.year}-$month-$day';
}

String _normalise(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _teamAliases(String team) {
  final normalised = _normalise(team);
  if (normalised.isEmpty) return const [];
  final values = <String>[normalised];
  final short = normalised
      .replaceFirst(RegExp(r'^(?:acf|afc|fc|sc|cf|cd|sv|tsg|1 fc)\s+'), '')
      .replaceFirst(RegExp(r'\s+(?:fc|afc|cf|bc|b c|football club)$'), '')
      .trim();
  if (short.length >= 4) values.add(short);

  const overrides = <String, List<String>>{
    'atalanta b c': ['atalanta'],
    'acf fiorentina': ['fiorentina'],
    'newcastle united': ['newcastle'],
    'newcastle utd': ['newcastle'],
    'fc bayern munchen': ['bayern munchen', 'bayern munich', 'bayern'],
    'athletic club': ['athletic bilbao', 'athletic club'],
    'sevilla fc': ['sevilla'],
    'ae prat': ['ae prat', 'prat'],
    'sporting hortaleza': ['sporting hortaleza'],
    'fc magdeburg': ['magdeburg'],
    '1 fc magdeburg': ['magdeburg'],
  };
  values.addAll(overrides[normalised] ?? const []);
  return values
      .map(_normalise)
      .where((value) => value.length >= 4)
      .toSet()
      .toList(growable: false);
}

bool _containsAlias(String body, List<String> aliases) => aliases.any(
      (alias) => ' $body '.contains(' $alias '),
    );

bool _isReplay(String body) => RegExp(
      r'\b(?:replay|repeat|re run|rebroadcast|recorded|highlights?|mini match|full impact|classic|recap|review|magazine|preview|match of the day|z zaznam|zaznam|aufzeichnung|ripetizione|rediffusion|resume|resumen|souhrn)\b',
      caseSensitive: false,
    ).hasMatch(body);
