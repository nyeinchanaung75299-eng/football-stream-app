import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/live_feed_controller.dart';

void main() {
  test(
    'overlapping refreshes share a request and preserve the last good data',
    () async {
      var calls = 0;
      var next = Completer<List<int>>();
      final feed = LiveFeedController(() {
        calls++;
        return next.future;
      });
      final first = feed.refresh();
      expect(feed.loading, isTrue);
      expect(feed.hasData, isFalse);
      expect(identical(first, feed.refresh()), isTrue);
      expect(calls, 1);
      next.complete([1]);
      await first;
      next = Completer<List<int>>();
      final refresh = feed.refresh();
      expect(feed.data, [1]);
      next.completeError(StateError('Temporary network failure'));
      await refresh;
      expect(feed.data, [1]);
      expect(feed.error, isA<StateError>());
      next = Completer<List<int>>();
      final empty = feed.refresh();
      next.complete([]);
      await empty;
      expect(feed.hasData, isTrue);
      expect(feed.data, isEmpty);
      expect(feed.error, isNull);
      feed.dispose();
    },
  );

  test(
    'first-load failure can be retried without an unhandled future error',
    () async {
      var fail = true;
      final feed = LiveFeedController(() async {
        if (fail) throw StateError('Offline');
        return [1];
      });
      await feed.refresh();
      expect(feed.hasData, isFalse);
      expect(feed.loading, isFalse);
      expect(feed.error, isA<StateError>());
      fail = false;
      await feed.refresh();
      expect(feed.data, [1]);
      expect(feed.error, isNull);
      feed.dispose();
    },
  );

  test(
    'leaving a page during loading prevents notifications after disposal',
    () async {
      final next = Completer<List<int>>();
      final feed = LiveFeedController(() => next.future);
      var notifications = 0;
      feed.addListener(() => notifications++);
      final pending = feed.refresh();
      feed.dispose();
      next.completeError(StateError('Offline'));
      await pending;
      expect(notifications, 1);
      await feed.refresh();
      expect(notifications, 1);
    },
  );
}
