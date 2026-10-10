import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/manual_source_url.dart';

void main() {
  test('recognizes standard direct stream URLs with signed queries', () {
    expect(
      detectManualStreamType('https://example.com/match/master.m3u8?sig=abc'),
      'hls',
    );
    expect(detectManualStreamType('https://media.example.org/live.mpd'), 'dash');
    expect(detectManualStreamType('http://example.com/live.flv'), 'flv');
    expect(detectManualStreamType('https://example.com/video.mp4'), 'mp4');
  });

  test('does not confuse websites or invalid schemes with live media', () {
    expect(isValidManualStreamUrl('https://playztv.online/'), isFalse);
    expect(isValidManualStreamUrl('https://example.com/watch.html',
        streamType: 'hls'), isFalse);
    expect(isValidManualStreamUrl('javascript:alert(1)',
        streamType: 'hls'), isFalse);
    expect(isValidManualStreamUrl('https://user:secret@example.com/live.m3u8'),
        isFalse);
    expect(isValidManualStreamUrl('ftp://example.com/live.m3u8'), isFalse);
  });

  test('explicit type permits extensionless authorized stream paths', () {
    expect(isValidManualStreamUrl('https://example.com/live/123'), isFalse);
    expect(isValidManualStreamUrl('https://example.com/live/123',
        streamType: 'hls'), isTrue);
    expect(isValidManualStreamUrl('https://example.com/master.m3u8'), isTrue);
  });
}
