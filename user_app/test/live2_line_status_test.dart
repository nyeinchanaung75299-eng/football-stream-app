import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/live2_line_status.dart';

void main() {
  test('URL alone is not evidence of HTTP or decoded playback', () {
    final status = Live2LineStatus.fromSource({
      'url': 'https://stream.example/video.m3u8',
      'healthStatus': 'healthy',
    });
    expect(status.link, 'FOUND');
    expect(status.http, 'NOT TESTED');
    expect(status.video, 'NOT VERIFIED');
    expect(status.provider, 'HEALTHY');
  });

  test('source health unknown never implies successful playback', () {
    final status = Live2LineStatus.fromSource({
      'url': 'https://stream.example/live.mpd',
      'healthStatus': 'unknown',
    });
    expect(status.summary, contains('HTTP: NOT TESTED'));
    expect(status.summary, contains('Video: NOT VERIFIED'));
  });

  test('HTTP status and confirmed video are independent', () {
    final status = Live2LineStatus.fromSource({
      'url': 'https://stream.example/live',
      'healthHttpStatus': 200,
      'playbackStatus': 'failed',
    });
    expect(status.http, '200 REACHABLE');
    expect(status.video, 'FAILED');
  });

  test('HTTP failures do not claim decoded video is healthy', () {
    final status = Live2LineStatus.fromSource({
      'stream_url': 'https://stream.example/live',
      'health_http_status': 403,
    });
    expect(status.http, '403 FAILED');
    expect(status.video, 'NOT VERIFIED');
  });

  test('only an explicit playback verification changes video state', () {
    final status = Live2LineStatus.fromSource({
      'url': 'https://stream.example/live',
      'health_http_status': '206',
      'playback_status': 'verified',
    });
    expect(status.http, '206 REACHABLE');
    expect(status.video, 'VERIFIED');
  });

  test('missing URLs are reported as missing', () {
    final status = Live2LineStatus.fromSource({});
    expect(status.link, 'MISSING');
    expect(status.http, 'NOT TESTED');
  });
}
