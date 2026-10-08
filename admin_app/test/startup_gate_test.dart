import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/startup_gate.dart';

void main() {
  testWidgets('Admin startup is visible and keeps the child gated until ready',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: StartupGate(
      initialize: () => pending.future,
      child: const Text('Authenticated UI'),
    )));
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Authenticated UI'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Authenticated UI'), findsOneWidget);
  });

  testWidgets('Admin startup failure offers a working retry', (tester) async {
    var fail = true;
    await tester.pumpWidget(MaterialApp(
        home: StartupGate(
      initialize: () async {
        if (fail) throw StateError('Offline');
      },
      child: const Text('Authenticated UI'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated UI'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated UI'), findsOneWidget);
  });

  testWidgets('Admin startup cannot spin forever when setup stalls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StartupGate(
      initialize: () => Completer<void>().future,
      child: const Text('Authenticated UI'),
    )));
    await tester.pump(const Duration(seconds: 13));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Authenticated UI'), findsNothing);
  });
}
