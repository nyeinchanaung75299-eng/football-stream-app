import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/playback_routes.dart';

void main() {
  test('places the VPN-free relay immediately after a protected direct URL', () {
    final result = addVpnFreePlaybackFallbacks([
      {
        'id': 'line-1',
        'label': 'Server 1',
        'url':
            'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
        'streamType': 'dash',
      },
    ]);

    expect(result, hasLength(2));
    expect(
      result[0]['url'],
      'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
    );
    expect(
      result[1]['url'],
      'https://nca-network-backup-test.vercel.app/p/token/manifest.mpd?e=1',
    );
    expect(result[1]['id'], 'line-1-vpn-free');
    expect(result[1]['label'], 'Server 1 • VPN-free backup');
  });

  test('supports stream_url rows and leaves direct provider URLs unchanged', () {
    final result = addVpnFreePlaybackFallbacks([
      {
        'id': 'protected',
        'stream_url':
            'https://football-api.nyeinchanaung.ccwu.cc/p/token/index.m3u8',
      },
      {
        'id': 'provider',
        'stream_url': 'https://video.example.com/live/index.m3u8',
      },
    ]);

    expect(result, hasLength(3));
    expect(
      result[1]['stream_url'],
      'https://nca-network-backup-test.vercel.app/p/token/index.m3u8',
    );
    expect(result[2]['id'], 'provider');
  });

  test('does not duplicate an existing Vercel playback source', () {
    final result = addVpnFreePlaybackFallbacks([
      {
        'id': 'direct',
        'url': 'https://football-api.nyeinchanaung.us.ci/p/token/video.flv',
      },
      {
        'id': 'existing-backup',
        'url': 'https://nca-network-backup-test.vercel.app/p/token/video.flv',
      },
    ]);

    expect(result, hasLength(2));
  });
}
