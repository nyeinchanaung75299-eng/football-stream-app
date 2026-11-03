import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/playback_routes.dart';
import 'package:football_viewer/widgets/player_server_rail.dart';

void main() {
  test('line chip drops duplicate provider name without losing the original line', () {
    expect(playerServerLabel({'label': 'ColaTV · ColaTV · Main'}, 0), 'ColaTV · Main');
    expect(playerServerLabel({'label': 'ColaTV · Line 2'}, 1), 'ColaTV · Line 2');
    expect(playerServerLabel({'label': 'https://example.com/private'}, 2), 'Line 3');
  });


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

  test('expanding an already expanded line list is idempotent', () {
    final first = addVpnFreePlaybackFallbacks([
      {
        'id': 'line-1',
        'label': 'Server 1',
        'url': 'https://football-api.nyeinchanaung.us.ci/p/token/live.mpd',
      },
    ]);
    final second = addVpnFreePlaybackFallbacks(first);

    expect(second, hasLength(2));
    expect(visiblePlaybackIndices(second), [0]);
  });



  test('line picker shows original routes only while retaining relays for auto-fallback', () {
    const directUrl = 'https://football-public-api.nyeinchanaung75299-eng.workers.dev/p/abc';
    final routes = addVpnFreePlaybackFallbacks([
      {'id':'cola-main','label':'ColaTV Main','url':directUrl},
      {'id':'cola-hls','label':'ColaTV HLS','url':'${directUrl}2'},
      {'id':'cola-flv','label':'ColaTV FLV','url':'${directUrl}3'},
      {'id':'cola-backup','label':'ColaTV Backup','url':'${directUrl}4'},
    ]);
    expect(routes.length, 8, reason:'Relays stay available for recovery');
    final visible = visiblePlaybackIndices(routes);
    expect(visible.length, 4, reason:'Do not display relay backups as selectable lines');
    expect(visible.map((index) => routes[index]['label']),
      ['ColaTV Main','ColaTV HLS','ColaTV FLV','ColaTV Backup']);
    expect(routes[1]['transport'], 'vercel-fallback');
  });

}
