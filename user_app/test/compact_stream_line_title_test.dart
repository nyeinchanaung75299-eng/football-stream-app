import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/widgets/compact_stream_line_title.dart';

void main() {
  test('keeps provider plus quality and HLS on one line', () {
    expect(compactStreamLineTitle(
      label: 'Soco Server 2 HD',
      streamType: 'hls',
      resolution: '1080p',
    ), 'Soco Server 2 HD • 1080p (HLS)');
  });
  test('avoids duplicating quality and stream type in names', () {
    expect(compactStreamLineTitle(
      label: 'Soco Server 2 • 720p (DASH)',
      streamType: 'dash',
      resolution: '720p',
    ), 'Soco Server 2 • 720p (DASH)');
  });
  test('falls back from unsafe URL-like labels without logging credentials', () {
    expect(compactStreamLineTitle(
      label: 'https://private.example.test/path?token=secret',
      streamType: 'm3u8',
      index: 4,
    ), 'Line 5 (HLS)');
  });
  test('does not create invented quality/format for unknown streams', () {
    expect(compactStreamLineTitle(
      label: 'Main server',
      streamType: 'auto',
      resolution: 'unknown',
    ), 'Main server');
  });
}
