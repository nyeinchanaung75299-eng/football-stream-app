import 'function_gateway.dart';

class HighlightsProvider {
  const HighlightsProvider(this.id, this.name, this.url, {this.websiteOnly = false});
  final String id;
  final String name;
  final String url;
  final bool websiteOnly;

  static const all = [
    HighlightsProvider('darkbyte', 'DarkByte', 'https://github.com/darkbyteprojects/iptv_png'),
    HighlightsProvider('dasfootball', 'DasFootball', 'https://dasfootball.com/'),
    HighlightsProvider('hoofoot', 'Hoofoot', 'https://hoofoot.net/'),
    HighlightsProvider('reddit', 'Reddit', 'https://www.reddit.com/r/footballhighlights/'),
    HighlightsProvider('soccerfullmatch', 'SoccerFullMatch', 'https://soccerfullmatch.com/', websiteOnly: true),
    HighlightsProvider('scorebat', 'ScoreBat', 'https://www.scorebat.com/', websiteOnly: true),
  ];
}

class HighlightsService {
  const HighlightsService();

  Future<Map<String, dynamic>> request(
    String provider, String action, [Map<String, dynamic> fields = const {}]
  ) async {
    final result = await FunctionGateway.invoke('source-match-list', body: {
      'source': 'highlights', 'provider': provider, 'action': action, ...fields,
    });
    if (result is! Map || result['source'] != 'highlights' || result['provider'] != provider) {
      throw const FormatException('The server returned a different highlights source.');
    }
    return Map<String, dynamic>.from(result);
  }
}

List<Map<String, dynamic>> highlightMaps(dynamic value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
    : [];

bool highlightMatchesQuery(Map<String, dynamic> row, String query) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  final text = '${row['title']} ${row['provider']}'.toLowerCase();
  return words.every(text.contains);
}

String highlightCopyDetails(Map<String, dynamic> line) => [
  line['stream_url']?.toString() ?? '',
  for (final field in ['referer', 'origin', 'user_agent'])
    if ((line[field]?.toString() ?? '').isNotEmpty)
      '${{'referer': 'Referer', 'origin': 'Origin', 'user_agent': 'User-Agent'}[field]}: ${line[field]}',
].join('\n');
