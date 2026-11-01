import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/public_guide_cache.dart';

void main() {
  test('same date shares one in-flight request across channel visits', () async {
    final cache = PublicGuideCache<int>();
    final pending = Completer<int>();
    var calls = 0;
    Future<int> fetch() {
      calls++;
      return pending.future;
    }

    final first = cache.load('2026-11-02', fetch);
    final second = cache.load('2026-11-02', fetch);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    pending.complete(7);
    expect(await first, 7);
    expect(await cache.load('2026-11-02', fetch), 7);
    expect(calls, 1);
  });

  test('explicit refresh and new Yangon date fetch fresh public EPG', () async {
    final cache = PublicGuideCache<int>();
    var calls = 0;
    Future<int> fetch() async => ++calls;

    expect(await cache.load('2026-11-02', fetch), 1);
    expect(await cache.load('2026-11-02', fetch), 1);
    expect(await cache.load('2026-11-02', fetch, refresh: true), 2);
    expect(await cache.load('2026-11-03', fetch), 3);
    expect(calls, 3);
  });

  test('failed public guide request is not cached as a permanent result', () async {
    final cache = PublicGuideCache<int>();
    var calls = 0;
    Future<int> fetch() async {
      calls++;
      if (calls == 1) throw StateError('temporary guide outage');
      return 9;
    }

    await expectLater(cache.load('2026-11-02', fetch), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(await cache.load('2026-11-02', fetch), 9);
    expect(calls, 2);
  });
}
