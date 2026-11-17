import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';
import 'package:football_admin/services/stream_detector_service.dart';

void main() {
  test('a single observed HLS candidate can return to CricHD quality picker', () {
    const hls = DetectedStream(
      url: 'https://cdn.example.org:7059/hls/live.m3u8?expires=100',
      type: 'hls',
      referer: 'https://playerbee.top/',
    );
    const segment = DetectedStream(url: 'https://cdn.example.org/v.mp4', type: 'mp4');
    expect(singleObservedHlsCandidate([segment, hls]), same(hls));
  });

  test('missing or ambiguous HLS candidates always retain manual detector', () {
    const first = DetectedStream(url: 'https://one.example.org/1.m3u8', type: 'hls');
    const second = DetectedStream(url: 'https://two.example.org/2.m3u8', type: 'hls');
    expect(singleObservedHlsCandidate([]), isNull);
    expect(singleObservedHlsCandidate([first, second]), isNull);
    expect(singleObservedHlsCandidate([
      const DetectedStream(url: 'https://one.example.org/a.mpd', type: 'dash'),
    ]), isNull);
    expect(singleObservedHlsCandidate([first, first]), same(first));
  });

  test('quick CricHD player is always the selected Link 1/Link 2', () {
    final selected = cricHdQuickDetectPlayer(
      {'watch_url': 'https://playerbee.top/charlie/fixture/link1'},
      {'browser_player_url': 'https://playerbee.top/charlie/fixture/link2'},
    );
    expect(selected?.path, '/charlie/fixture/link1');
  });

  test('untrusted selected watch page cannot be replaced by an arbitrary page', () {
    expect(cricHdQuickDetectPlayer({
      'watch_url': 'https://untrusted.example.org/anything'
    }, {'browser_player_url': 'https://playerbee.top/charlie/fixture/link2'}), isNull);
    expect(cricHdQuickDetectPlayer(
      {}, {'browser_player_url': 'https://playerbee.top/charlie/fixture/link2'},
    )?.path, '/charlie/fixture/link2');
  });
}
