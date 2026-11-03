import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  test('all source statuses run with bounded parallelism', () async {
    var active = 0;
    var maximum = 0;
    final completed = <int>[];

    await runBoundedStatusChecks<int>(
      List.generate(24, (index) => index),
      12,
      (item) async {
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(
          Duration(milliseconds: item.isEven ? 2 : 5),
        );
        completed.add(item);
        active--;
      },
    );

    expect(completed.toSet(), Set<int>.from(List.generate(24, (i) => i)));
    expect(maximum, 12);
    expect(active, 0);
  });
}
