import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/source_line_loader.dart';

Map<String, dynamic> line(String id, int priority) => {
  'id': id,
  'stream_url': 'https://example.test/$id.m3u8',
  'priority': priority,
};

SourceLineLoader loader(List<Future<SourceLines> Function()> anchors) =>
    SourceLineLoader(
      anchors: anchors,
      compare: (a, b) => (a['priority'] as int).compareTo(b['priority'] as int),
    );

void main() {
  test(
    'first anchor appears before slow backup and keeps its selected index',
    () async {
      final slow = Completer<SourceLines>();
      final operation = loader([
        () async => [line('first', 5)],
        () => slow.future,
      ]);
      operation.start();
      expect((await operation.firstUsable)!.single['id'], 'first');
      expect(operation.loading, isTrue);
      final selectedId = operation.rows[0]['id'];
      slow.complete([line('backup', 0), line('first', 5)]);
      await operation.settled;
      expect(operation.rows.map((row) => row['id']), ['first', 'backup']);
      expect(operation.rows[0]['id'], selectedId);
      expect(operation.loading, isFalse);
      operation.dispose();
    },
  );

  test('empty anchor does not hide a later usable backup', () async {
    final late = Completer<SourceLines>();
    final operation = loader([() async => [], () => late.future]);
    var firstCompleted = false;
    unawaited(operation.firstUsable.then((_) => firstCompleted = true));
    operation.start();
    await Future<void>.delayed(Duration.zero);
    expect(firstCompleted, isFalse);
    late.complete([line('late', 0)]);
    expect((await operation.firstUsable)!.single['id'], 'late');
    operation.dispose();
  });

  test(
    'all-empty successful anchors remain an authoritative empty result',
    () async {
      final operation = loader([() async => [], () async => []]);
      operation.start();
      expect(await operation.firstUsable, isEmpty);
      expect(await operation.settled, isEmpty);
      operation.dispose();
    },
  );

  test(
    'an empty success remains valid even when another anchor fails',
    () async {
      final operation = loader([
        () async => [],
        () async => throw StateError('Unavailable'),
      ]);
      operation.start();
      expect(await operation.firstUsable, isEmpty);
      operation.dispose();
    },
  );

  test(
    'all failed anchors report failure instead of a false empty result',
    () async {
      final operation = loader([() async => throw StateError('Unavailable')]);
      final failure = expectLater(operation.firstUsable, throwsStateError);
      operation.start();
      await failure;
      operation.dispose();
    },
  );

  test(
    'dismissal cancels immediately and late responses do not notify',
    () async {
      final late = Completer<SourceLines>();
      final operation = loader([() => late.future]);
      var notifications = 0;
      operation.addListener(() => notifications++);
      operation.start();
      operation.cancel();
      expect(await operation.firstUsable, isNull);
      expect(await operation.settled, isNull);
      late.complete([line('late', 0)]);
      await Future<void>.delayed(Duration.zero);
      expect(operation.rows, isEmpty);
      expect(notifications, 0);
      operation.dispose();
    },
  );
}
