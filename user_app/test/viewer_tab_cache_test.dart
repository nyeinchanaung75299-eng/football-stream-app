import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/live_feed_controller.dart';
import 'package:football_viewer/viewer_tab_cache.dart';

void main() {
  test('YYZB -> Soco -> YYZB uses last successful result without reload',
      () async {
    var requests = 0;
    Future<List<Map<String, dynamic>>> fetch() async {
      requests++;
      return [{'id': 'room-1'}];
    }

    expect((await ViewerTabCache.loadSource('test-yyzb', fetch)).length, 1);
    expect((await ViewerTabCache.loadSource('test-soco', fetch)).length, 1);
    expect((await ViewerTabCache.loadSource('test-yyzb', fetch)).length, 1);
    expect(requests, 2);
    ViewerTabCache.saveSourceUi('test-yyzb', const ViewerSourceUiState(
      query: 'football', league: 'Premier League', scrollOffset: 290,
    ));
    final saved = ViewerTabCache.sourceUi('test-yyzb');
    expect(saved.query, 'football');
    expect(saved.scrollOffset, 290);
  });

  test('forced successful empty result removes deleted matches', () async {
    const source = 'test-empty-authoritative';
    await ViewerTabCache.loadSource(source,
        () async => [{'id': 'deleted-match'}]);
    expect(ViewerTabCache.sourceRows(source)!.length, 1);
    await ViewerTabCache.loadSource(source, () async => [], force: true);
    expect(ViewerTabCache.sourceRows(source), isEmpty);
    final rows = await ViewerTabCache.loadSource(source,
        () => throw StateError('Must not fetch fresh empty cache'));
    expect(rows, isEmpty);
  });

  test('concurrent source requests are single flight', () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    var count = 0;
    Future<List<Map<String, dynamic>>> fetch() {
      count++;
      return gate.future;
    }
    final first = ViewerTabCache.loadSource('test-inflight', fetch);
    final second = ViewerTabCache.loadSource('test-inflight', fetch);
    expect(identical(first, second), isTrue);
    expect(count, 1);
    gate.complete([{'id': 'only'}]);
    await Future.wait([first, second]);
    expect(count, 1);
  });

  test('network failure keeps cached rows and allows next retry', () async {
    const source = 'test-offline';
    await ViewerTabCache.loadSource(source, () async => [{'id': 'safe'}]);
    await expectLater(
      ViewerTabCache.loadSource(source, () async {
        throw StateError('offline');
      }, force: true),
      throwsStateError,
    );
    expect(ViewerTabCache.sourceRows(source)?.first['id'], 'safe');
    await ViewerTabCache.loadSource(source, () async => [], force: true);
    expect(ViewerTabCache.sourceRows(source), isEmpty);
  });

  test('channels reuse success, refresh force and preserve filters', () async {
    var count = 0;
    Future<List<Map<String, dynamic>>> fetch() async {
      count++;
      return [{'id': 'channel-1'}];
    }
    await ViewerTabCache.loadChannels(fetch, force: true);
    await ViewerTabCache.loadChannels(fetch);
    expect(count, 1);
    ViewerTabCache.channelUi = const ViewerChannelsUiState(
      search: 'bein', group: 'Sports', scrollOffset: 120,
    );
    expect(ViewerTabCache.channelUi.group, 'Sports');
    expect(ViewerTabCache.channelUi.scrollOffset, 120);
    await ViewerTabCache.loadChannels(() async => [], force: true);
    expect(ViewerTabCache.channelRows, isEmpty);
  });

  test('persisted Live seed never resurrects a successful empty feed', () async {
    final feed = LiveFeedController<List<int>>(() async => []);
    feed.seedIfMissing([1, 2]);
    expect(feed.data, [1, 2]);
    await feed.refresh();
    expect(feed.data, isEmpty);
    feed.seedIfMissing([5]);
    expect(feed.data, isEmpty);
    feed.dispose();
  });
}
