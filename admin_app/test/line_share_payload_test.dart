import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/line_share_payload.dart';

void main() {
  test('exports the complete selected line but no unrelated account fields',
      () {
    final payload = LineSharePayload('Singapore vs Brazil', [
      {
        'label': 'SporTV',
        'stream_type': 'dash',
        'stream_url': 'https://cdn.example/live.mpd?a=1&token=a+b%2F',
        'referer': 'https://player.example/watch?x=1&y=2',
        'origin': 'https://player.example',
        'key_id': 'example-id',
        'key_data': 'example-key',
        'cookie': 'private-session',
        'authorization': 'private-auth',
        'admin_id': 'private-user',
      }
    ]);
    expect(payload.text, contains('Key ID: example-id\nKey Data: example-key'));
    expect(payload.text,
        contains('Referer: https://player.example/watch?x=1&y=2'));
    expect(payload.text, isNot(contains('private-')));
    final uri = payload.telegramUri!;
    expect(uri.host, 't.me');
    expect(uri.queryParameters['url'], payload.lines.first['stream_url']);
    expect(uri.queryParameters['text'], contains('Key Data: example-key'));
    expect(uri.queryParameters.keys, unorderedEquals(['url', 'text']));
  });
  test(
      'whole match retains every line and long payload switches to file export',
      () {
    final payload = LineSharePayload(
        'Bayern vs Köln / Match',
        List.generate(
            40,
            (i) => {
                  'label': 'Line $i',
                  'stream_type': 'hls',
                  'stream_url':
                      'https://cdn.example/$i.m3u8?token=${'a' * 200}',
                }));
    expect(payload.text, contains('40. Line 39'));
    expect(payload.telegramUri, isNull);
    expect(payload.filename, endsWith('-lines.txt'));
    expect(payload.filename, isNot(contains('/')));
    expect(payload.matchName, 'Bayern vs Köln / Match');
  });
}
