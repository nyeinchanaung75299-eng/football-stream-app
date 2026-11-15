import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/playback_routes.dart';
import 'package:football_viewer/network_endpoints.dart';
import 'package:football_viewer/widgets/player_server_rail.dart';

void main() {
  test(
    'event lines start on Cloudflare while retaining an internal Vercel fallback',
    () {
      final original = {
        'id': 'one',
        'label': 'Sports',
        'url':
            'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
        'headers': {'Referer': 'https://provider.example/'},
        'keyId': 'test-key-id',
        'keyData': 'test-key-data',
      };
      final result = playbackSources([original]);
      expect(result, hasLength(1));
      expect(
        result.single['url'],
        '$cloudflarePublicBase/p/token/manifest.mpd?e=1',
      );
      expect(
        result.single['routeFallbackUrl'],
        '$vercelBackupBase/p/token/manifest.mpd?e=1',
      );
      for (final field in ['id', 'label', 'headers', 'keyId', 'keyData'])
        expect(result.single[field], original[field]);
      expect(
        original['url'],
        'https://football-api.nyeinchanaung.us.ci/p/token/manifest.mpd?e=1',
      );
      expect(visiblePlaybackIndices(result), [0]);
    },
  );
  test('ordinary channel playback never adds or chooses a Vercel copy', () {
    final result = playbackSources([
      {'id': 'channel', 'stream_url': '$legacyVercelBase/p/session/index.m3u8'},
    ], useVercel: false);
    expect(result, hasLength(1));
    expect(result.single.containsKey('routeFallbackUrl'), false);
    expect(
      result.single['stream_url'],
      '$cloudflarePublicBase/p/session/index.m3u8',
    );
    expect(
      playbackSources(result, useVercel: true).single['stream_url'],
      '$vercelBackupBase/p/session/index.m3u8',
    );
  });
  test(
    'explicit Vercel channels stay single-route and events are idempotent',
    () {
      final events = playbackSources([
        {'url': '$vercelBackupBase/p/token/index.m3u8?session=opaque'},
      ]);
      expect(playbackSources(events), events);
      final explicit = playbackSources(events, useVercel: true).single;
      expect(
        explicit['url'],
        '$vercelBackupBase/p/token/index.m3u8?session=opaque',
      );
      expect(explicit.containsKey('routeFallbackUrl'), false);
    },
  );
  test('untrusted fallback URLs cannot turn direct playback into a relay', () {
    for (final url in [
      'https://provider.example/live.m3u8',
      'https://attacker.example/p/token',
      '$cloudflarePublicBase/health',
    ]) {
      final row = playbackSources([
        {
          'url': url,
          'routeFallbackUrl': 'https://attacker.example/p/credential',
        },
      ]).single;
      expect(row['url'], url);
      expect(row.containsKey('routeFallbackUrl'), false);
    }
  });
  test('legacy aliases collapse without hiding different real streams', () {
    final result = playbackSources([
      {'id': 'main', 'label': 'Main', 'url': '$cloudflarePublicBase/p/token'},
      {'id': 'main-copy', 'url': '$legacyVercelBase/p/token'},
      {
        'id': 'main-cloudflare-alt',
        'transport': 'cloudflare-fallback',
        'url': 'https://football-api.nyeinchanaung.ccwu.cc/p/token',
      },
      {
        'id': 'second',
        'label': 'Second',
        'url': '$cloudflarePublicBase/p/other',
      },
    ]);
    expect(result, hasLength(2));
    expect(visiblePlaybackIndices(result), [0, 1]);
    expect(result.map((r) => r['label']), ['Main', 'Second']);
    expect(playbackSources(result), result);
  });
  test('saved fallback-only data migrates to one readable original line', () {
    final result = playbackSources([
      {
        'id': 'one-cloudflare-alt',
        'label': 'Sports • Network backup',
        'transport': 'cloudflare-fallback',
        'url': 'https://football-api.nyeinchanaung.ccwu.cc/p/token',
      },
    ]);
    expect(result.single['id'], 'one');
    expect(result.single['label'], 'Sports');
    expect(result.single.containsKey('transport'), false);
  });
  test('direct providers and unapproved URL hosts are not changed', () {
    for (final url in [
      'https://provider.example/video.m3u8',
      'https://attacker.example/p/token',
      'https://user@football-api.nyeinchanaung.us.ci/p/token',
    ]) {
      expect(
        playbackSources([
          {'url': url},
        ]).single['url'],
        url,
      );
    }
  });
  test(
    'display labels retain real choices without duplicate provider names',
    () {
      expect(
        playerServerLabel({'label': 'ColaTV · ColaTV · Main'}, 0),
        'ColaTV · Main',
      );
      expect(
        playerServerLabel({'label': 'ColaTV · Line 2'}, 1),
        'ColaTV · Line 2',
      );
    },
  );
}
