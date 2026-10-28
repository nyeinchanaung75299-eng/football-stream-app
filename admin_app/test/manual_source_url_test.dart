import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/manual_source_url.dart';
import 'package:football_admin/source_line_validation.dart';

void main() {
  test('recognizes standard direct stream URLs with signed queries', () {
    expect(
      detectManualStreamType('https://example.com/match/master.m3u8?sig=abc'),
      'hls',
    );
    expect(
      detectManualStreamType('https://media.example.org/live.mpd'),
      'dash',
    );
    expect(detectManualStreamType('http://example.com/live.flv'), 'flv');
    expect(detectManualStreamType('https://example.com/video.mp4'), 'mp4');
  });

  test('does not confuse websites or invalid schemes with live media', () {
    expect(isValidManualStreamUrl('https://playztv.online/'), isFalse);
    expect(
      isValidManualStreamUrl(
        'https://example.com/watch.html',
        streamType: 'hls',
      ),
      isFalse,
    );
    expect(
      isValidManualStreamUrl('javascript:alert(1)', streamType: 'hls'),
      isFalse,
    );
    expect(
      isValidManualStreamUrl('https://user:secret@example.com/live.m3u8'),
      isFalse,
    );
    expect(isValidManualStreamUrl('ftp://example.com/live.m3u8'), isFalse);
  });

  test('Website pages cannot be imported as media', () {
    for (final page in [
      'https://example.com/watch',
      'https://example.com/football',
      'https://example.com/football/competition/premier-league',
      'https://example.com/channels',
      'https://example.net/channels',
    ]) {
      expect(isValidManualStreamUrl(page, streamType: 'hls'), isFalse);
    }
    expect(
      isValidManualStreamUrl('https://cdn.example.org/live/master.m3u8'),
      isTrue,
    );
  });

  test('explicit type permits extensionless authorized stream paths', () {
    expect(isValidManualStreamUrl('https://example.com/live/123'), isFalse);
    expect(
      isValidManualStreamUrl('https://example.com/live/123', streamType: 'hls'),
      isTrue,
    );
    expect(isValidManualStreamUrl('https://example.com/master.m3u8'), isTrue);
  });

  test('manual ClearKey requires a complete DASH hexadecimal pair', () {
    expect(
      manualClearKeyError(streamType: 'hls', keyId: '', keyData: ''),
      isNull,
    );
    expect(
      manualClearKeyError(
        streamType: 'hls',
        keyId: '00112233445566778899aabbccddeeff',
        keyData: 'ffeeddccbbaa99887766554433221100',
      ),
      contains('DASH'),
    );
    expect(
      manualClearKeyError(
        streamType: 'dash',
        keyId: '00112233-4455-6677-8899-aabbccddeeff',
        keyData: 'FFEEDDCCBBAA99887766554433221100',
      ),
      isNull,
    );
    expect(
      manualClearKeyError(
        streamType: 'dash',
        keyId: '00112233445566778899aabbccddeeff',
        keyData: '',
      ),
      contains('both'),
    );
  });
}
