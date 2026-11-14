import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/playback_routes.dart';
import 'package:football_viewer/widgets/player_server_rail.dart';

void main() {
  test(
    'line chip drops duplicate provider name without losing the original line',
    () {
      expect(
        playerServerLabel({'label': 'ColaTV · ColaTV · Main'}, 0),
        'ColaTV · Main',
      );
      expect(
        playerServerLabel({'label': 'ColaTV · Line 2'}, 1),
        'ColaTV · Line 2',
      );
      expect(
        playerServerLabel({'label': 'https://example.com/private'}, 2),
        'Line 3',
      );
    },
  );

  test('tries a second Cloudflare alias before the operator media relay', () {
    final result = addVpnFreePlaybackFallbacks([
      {
        'id': 'line-1',
        'label': 'Server 1',
        'url':
            'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
        'streamType': 'dash',
        'headers': {'Referer': 'https://provider.example/'},
        'keyId': 'test-key-id',
        'key': 'test-key-data',
      },
    ]);

    expect(result, hasLength(3));
    expect(
      result[0]['url'],
      'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
    );
    expect(
      result[2]['url'],
      'https://nca-network-backup-test.vercel.app/p/token/manifest.mpd?e=1',
    );
    for (final row in result) {
      expect(row['headers'], {'Referer': 'https://provider.example/'});
      expect(row['keyId'], 'test-key-id');
      expect(row['key'], 'test-key-data');
    }
    expect(result[1]['transport'], 'cloudflare-fallback');
    expect(result[2]['id'], 'line-1-vpn-free');
    expect(result[2]['label'], 'Server 1 • VPN-free backup');
  });

  test(
    'supports stream_url rows and leaves direct provider URLs unchanged',
    () {
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

      expect(result, hasLength(4));
      expect(
        result[2]['stream_url'],
        'https://nca-network-backup-test.vercel.app/p/token/index.m3u8',
      );
      expect(result[3]['id'], 'provider');
    },
  );

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

    expect(result, hasLength(3));
  });

  test('expanding an already expanded line list is idempotent', () {
    final first = addVpnFreePlaybackFallbacks([
      {
        'id': 'line-1',
        'label': 'Server 1',
        'url': 'https://football-api.nyeinchanaung.us.ci/p/token/live.mpd',
      },
    ]);
    final second = addVpnFreePlaybackFallbacks(first);

    expect(second, hasLength(3));
    expect(visiblePlaybackIndices(second), [0]);
  });

  test(
    'line picker shows original routes only while retaining relays for auto-fallback',
    () {
      const directUrl =
          'https://football-public-api.nyeinchanaung75299-eng.workers.dev/p/abc';
      final routes = addVpnFreePlaybackFallbacks([
        {'id': 'cola-main', 'label': 'ColaTV Main', 'url': directUrl},
        {'id': 'cola-hls', 'label': 'ColaTV HLS', 'url': '${directUrl}2'},
        {'id': 'cola-flv', 'label': 'ColaTV FLV', 'url': '${directUrl}3'},
        {'id': 'cola-backup', 'label': 'ColaTV Backup', 'url': '${directUrl}4'},
        {'id': 'channel-nbc', 'label': 'NBC Server 1', 'url': '${directUrl}5'},
      ]);
      expect(
        routes.length,
        15,
        reason: 'Try Cloudflare aliases before the operator relay',
      );
      final visible = visiblePlaybackIndices(routes);
      expect(
        visible.length,
        5,
        reason: 'Do not display relay backups as selectable lines',
      );
      expect(visible.map((index) => routes[index]['label']), [
        'ColaTV Main',
        'ColaTV HLS',
        'ColaTV FLV',
        'ColaTV Backup',
        'NBC Server 1',
      ]);
      expect(
        routes[visible.last]['id'],
        'channel-nbc',
        reason: 'The last visible selection uses its playback index',
      );
      expect(routes[visible.last + 2]['transport'], 'vercel-fallback');
      expect(routes[1]['transport'], 'cloudflare-fallback');
    },
  );
}
