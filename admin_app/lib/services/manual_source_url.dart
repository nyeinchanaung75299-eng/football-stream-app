// Admin-only manual stream URL checks for providers with no verified public
// listing API. Does not fetch private app endpoints or resolve protected links.
const _directTypes = {'hls', 'dash', 'flv', 'mp4'};

Uri? _parseWebStreamUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

String? detectManualStreamType(String value) {
  final uri = _parseWebStreamUrl(value);
  if (uri == null) return null;
  final path = uri.path.toLowerCase();
  if (path.endsWith('.m3u8')) return 'hls';
  if (path.endsWith('.mpd')) return 'dash';
  if (path.endsWith('.flv')) return 'flv';
  if (path.endsWith('.mp4')) return 'mp4';
  return null;
}

bool isValidManualStreamUrl(String value, {String streamType = 'auto'}) {
  final uri = _parseWebStreamUrl(value);
  if (uri == null) return false;
  final path = uri.path.toLowerCase();
  // A website page is not a playable media link, even with an explicit type.
  if (RegExp(r'\.(html?|php|aspx?)$').hasMatch(path)) return false;
  final host = uri.host.toLowerCase();
  final isTflix = host == 'tflix.su' ||
      host == 'tflix.club' ||
      host.endsWith('.tflix.su') ||
      host.endsWith('.tflix.club');
  if (isTflix &&
      (path == '/' ||
          path == '/watch' ||
          path == '/channels' ||
          path == '/football' ||
          path.startsWith('/football/') ||
          path.startsWith('/match/') ||
          path.startsWith('/channel/'))) {
    return false;
  }
  final detected = detectManualStreamType(value);
  return detected != null ||
      (_directTypes.contains(streamType) && path.isNotEmpty && path != '/');
}
