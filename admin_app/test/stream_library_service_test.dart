import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/stream_library_service.dart';

void main() {
  test('Library accepts HLS but rejects other media and website pages', () {
    expect(
      validateHlsLibraryInput(
        label: 'Main HD',
        streamUrl: 'https://media.example.test/live/master.m3u8?token=secret',
      ),
      isNull,
    );
    expect(
      validateHlsLibraryInput(
        label: 'Extensionless HLS',
        streamUrl: 'https://media.example.test/live/channel-1',
      ),
      isNull,
    );
    expect(
      validateHlsLibraryInput(
        label: 'Wrong type',
        streamUrl: 'https://media.example.test/live/manifest.mpd',
      ),
      contains('HLS'),
    );
    expect(
      validateHlsLibraryInput(
        label: 'Website',
        streamUrl: 'https://example.com/football',
      ),
      contains('HLS'),
    );
  });

  test('Library validates optional headers and strips empty values', () {
    expect(
      validateHlsLibraryInput(
        label: 'Main',
        streamUrl: 'https://media.example.test/live.m3u8',
        referer: 'javascript:alert(1)',
      ),
      contains('HTTP'),
    );
    expect(
      streamLibraryPayload(
        label: ' Main ',
        streamUrl: ' https://media.example.test/live.m3u8 ',
      ),
      {
        'label': 'Main',
        'stream_type': 'hls',
        'stream_url': 'https://media.example.test/live.m3u8',
        'referer': null,
        'origin': null,
      },
    );
  });

  test('Library payload can never contain DRM key fields', () {
    final payload = streamLibraryPayload(
      label: 'Authorized HLS',
      streamUrl: 'https://media.example.test/live.m3u8',
      referer: 'https://app.example.test/watch',
      origin: 'https://app.example.test',
    );
    expect(payload['stream_type'], 'hls');
    expect(payload, isNot(contains('key_id')));
    expect(payload, isNot(contains('key_data')));
  });

  test('safe Library label never displays signed query data', () {
    expect(
      safeStreamLocation(
        'https://cdn.example.test/path/master.m3u8?token=do-not-show#part',
      ),
      'cdn.example.test/path/master.m3u8',
    );
  });
}
