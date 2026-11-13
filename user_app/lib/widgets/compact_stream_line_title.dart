/// Keeps the stream provider name while removing a repository fixture prefix.
String shortMatchLineLabel(String label) {
  final original = label.trim();
  final match = RegExp(
    r'^[^•·\n]{1,90}\s+(?:vs\.?|v)\s+[^•·\n]{1,90}\s*[•·]\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(original);
  final server = match?.group(1)?.trim() ?? '';
  return server.isEmpty ? original : server;
}

/// Compact, public-only line text for all Viewer source choosers.
///
/// Never append probe/HTTP/debug diagnostics to the visible selection rows.
/// Retain the original line label, append known quality only when absent, and
/// present the type in parentheses on the same line.
String compactStreamLineTitle({
  required String label,
  required String streamType,
  String resolution = '',
  int index = 0,
}) {
  final raw = shortMatchLineLabel(label);
  final unsafe = raw.length > 120 ||
      RegExp(r'https?://|(?:authorization|token|referer|keydata|keyid)\s*[:=]', caseSensitive: false)
          .hasMatch(raw);
  var title = raw.isEmpty || unsafe ? 'Line ${index + 1}' : raw;
  final quality = resolution.trim();
  if (RegExp(r'^(?:\d{3,4}p|hd|sd|fhd|uhd|4k)$', caseSensitive: false)
          .hasMatch(quality) &&
      !title.toLowerCase().contains(quality.toLowerCase())) {
    title = '$title • $quality';
  }
  final type = switch (streamType.trim().toLowerCase()) {
    'm3u8' || 'hls' => 'HLS',
    'mpd' || 'dash' => 'DASH',
    'mp4' => 'MP4',
    'flv' => 'FLV',
    _ => '',
  };
  if (type.isNotEmpty &&
      !RegExp('\\b' + type + '\\b', caseSensitive: false).hasMatch(title)) {
    title = '$title ($type)';
  }
  return title;
}
