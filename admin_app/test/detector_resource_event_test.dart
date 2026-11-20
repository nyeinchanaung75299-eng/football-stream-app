import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/detector_resource_observer.dart';

void main() {
  test(
      'iframe observation preserves frame Referer and only explicit media association',
      () {
    final event = DetectorResourceEvent.parse({
      'documentId': 'current-doc',
      'pageUrl': 'https://playerbee.top/charlie/event/1',
      'frameUrl': 'https://iframe.example/player',
      'urls': [
        'https://cdn.example/live.m3u8',
        'https://cdn.example/seg.ts',
        'blob:https://iframe.example/1'
      ],
      'mediaUrls': ['blob:https://iframe.example/1'],
      'cookie': 'not-exported',
    })!;
    expect(event.streams.length, 1);
    expect(event.streams.single.referer, 'https://iframe.example/player');
    expect(event.mediaUrls, isEmpty);
  });
  test(
      'malformed events and credential-bearing page URLs never enter the session',
      () {
    for (final value in [
      null,
      {},
      {
        'documentId': 'x',
        'pageUrl': 'https://user:secret@example.com',
        'frameUrl': 'https://example.com',
        'urls': [],
        'mediaUrls': []
      }
    ]) {
      expect(DetectorResourceEvent.parse(value), isNull);
    }
  });
}
