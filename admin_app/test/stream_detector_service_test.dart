import 'package:flutter_test/flutter_test.dart';

import '../lib/services/stream_detector_service.dart';

void main() {
  test('recognizes direct HLS and DASH requests', () {
    final hls = DetectedStream.fromRequest(
      'https://cdn.example.com/live/master.m3u8?token=temporary',
      pageUrl: 'https://tv.example.com/watch',
    );
    expect(hls?.type, 'hls');
    expect(hls?.referer, 'https://tv.example.com/watch');
    expect(hls?.origin, 'https://tv.example.com');

    final dash = DetectedStream.fromRequest(
      'https://cdn.example.com/manifest.mpd',
    );
    expect(dash?.type, 'dash');
    expect(dash?.origin, '');
  });

  test('recognizes MP4, FLV and query-format HLS', () {
    expect(
      DetectedStream.fromRequest('https://media.example.com/a.mp4')?.type,
      'mp4',
    );
    expect(
      DetectedStream.fromRequest('https://media.example.com/a.flv')?.type,
      'flv',
    );
    expect(
      DetectedStream.fromRequest('https://media.example.com/watch?format=m3u8')
          ?.type,
      'hls',
    );
  });

  test('filters nonstream traffic, segments and unsafe schemes', () {
    for (final url in [
      'https://example.com/watch',
      'https://example.com/video.ts',
      'https://example.com/chunk.m4s',
      'javascript:alert(1)',
      'file:///private/movie.m3u8',
      'https://name:pass@example.com/live.m3u8',
    ]) {
      expect(DetectedStream.fromRequest(url), isNull, reason: url);
    }
  });

  test('uses only Referer and Origin, ignoring sensitive headers', () {
    final item = DetectedStream.fromRequest(
      'https://cdn.example.com/stream.m3u8',
      pageUrl: 'https://example.com/fallback',
      headers: {
        'rEfErEr': 'https://example.com/player',
        'ORIGIN': 'https://example.com',
        'Cookie': 'session=topsecret',
        'Authorization': 'Bearer topsecret',
      },
    )!;
    expect(item.referer, 'https://example.com/player');
    expect(item.origin, 'https://example.com');
    expect(item.url, isNot(contains('topsecret')));
    expect(item.referer, isNot(contains('topsecret')));
  });
}
