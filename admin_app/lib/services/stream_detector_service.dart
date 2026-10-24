/// Stream discovery for media that the administrator is authorized to use.
/// Only URLs and Referer/Origin are retained; never store cookies or auth tokens.
class DetectedStream {
  const DetectedStream({
    required this.url,
    required this.type,
    this.referer = '',
    this.origin = '',
  });

  final String url;
  final String type;
  final String referer;
  final String origin;

  static DetectedStream? fromRequest(
    String rawUrl, {
    String? pageUrl,
    Map<String, String>? headers,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    final path = uri.path.toLowerCase();
    String? type;
    if (path.endsWith('.m3u8')) {
      type = 'hls';
    } else if (path.endsWith('.mpd')) {
      type = 'dash';
    } else if (path.endsWith('.mp4')) {
      type = 'mp4';
    } else if (path.endsWith('.flv')) {
      type = 'flv';
    } else {
      // Some services put the media format in a query parameter.
      for (final key in ['format', 'type', 'extension']) {
        final format = uri.queryParameters[key]?.toLowerCase();
        if (format == 'm3u8' || format == 'hls') {
          type = 'hls';
          break;
        }
        if (format == 'mpd' || format == 'dash') {
          type = 'dash';
          break;
        }
        if (format == 'mp4' || format == 'flv') {
          type = format;
          break;
        }
      }
    }
    if (type == null) return null;

    String? header(String name) {
      if (headers == null) return null;
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
      }
      return null;
    }

    String validatedUrl(String? candidate) {
      final value = candidate?.trim() ?? '';
      final candidateUri = Uri.tryParse(value);
      if (candidateUri == null ||
          !const {'http', 'https'}.contains(candidateUri.scheme.toLowerCase()) ||
          candidateUri.host.isEmpty ||
          candidateUri.userInfo.isNotEmpty) {
        return '';
      }
      return value;
    }

    final referrer = validatedUrl(header('referer'));
    final page = validatedUrl(pageUrl);
    final originHeader = validatedUrl(header('origin'));
    final originSource = Uri.tryParse(referrer.isNotEmpty ? referrer : page);
    return DetectedStream(
      url: uri.toString(),
      type: type,
      referer: referrer.isNotEmpty ? referrer : page,
      origin: originHeader.isNotEmpty
          ? Uri.parse(originHeader).origin
          : (originSource?.hasAuthority == true ? originSource!.origin : ''),
    );
  }
}
