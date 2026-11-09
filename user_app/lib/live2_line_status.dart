/// Distinguish a stream URL, an HTTP/media probe, and decoded playback.
///
/// A resolver may return a URL with 'health_status: healthy' while running
/// with skip_probe=true. That is not proof of HTTP reachability or video.
class Live2LineStatus {
  const Live2LineStatus({
    required this.link,
    required this.http,
    required this.video,
    required this.provider,
  });

  final String link;
  final String http;
  final String video;
  final String provider;

  factory Live2LineStatus.fromSource(Map<String, dynamic> source) {
    final url = (source['url'] ?? source['stream_url'] ?? '').toString().trim();
    final rawHttp = source['healthHttpStatus'] ??
        source['health_http_status'];
    final httpCode = rawHttp is int
        ? rawHttp
        : int.tryParse(rawHttp?.toString() ?? '');

    final rawPlayback = (source['playbackStatus'] ??
            source['playback_status'] ?? '')
        .toString().trim().toLowerCase();
    final health = (source['healthStatus'] ??
            source['health_status'] ?? 'unknown')
        .toString().trim().toLowerCase();

    return Live2LineStatus(
      link: url.isEmpty ? 'MISSING' : 'FOUND',
      http: httpCode == null
          ? 'NOT TESTED'
          : httpCode >= 200 && httpCode < 400
              ? '$httpCode REACHABLE'
              : '$httpCode FAILED',
      video: switch (rawPlayback) {
        'verified' => 'VERIFIED',
        'failed' => 'FAILED',
        _ => 'NOT VERIFIED',
      },
      provider: switch (health) {
        'healthy' => 'HEALTHY',
        'slow' => 'SLOW',
        'failed' || 'dead' => 'FAILED',
        _ => 'UNKNOWN',
      },
    );
  }

  String get summary => 'Link: $link  •  HTTP: $http  •  Video: $video';
}
