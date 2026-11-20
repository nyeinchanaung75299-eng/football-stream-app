import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/guide_clock.dart';

class ClockProbe extends StatefulWidget {
  const ClockProbe(
      {super.key,
      required this.now,
      required this.boundary,
      this.active = true});
  final DateTime Function() now;
  final DateTime? boundary;
  final bool active;
  @override
  State<ClockProbe> createState() => _ClockProbeState();
}

class _ClockProbeState extends State<ClockProbe> with GuideClock<ClockProbe> {
  @override
  bool get guideClockActive => widget.active;
  @override
  DateTime get guideNow => widget.now();
  @override
  DateTime? nextGuideBoundary(DateTime now) =>
      widget.boundary?.isAfter(now) == true ? widget.boundary : null;
  @override
  Widget build(BuildContext context) => Text('revision:$guideClockRevision');
}

void main() {
  testWidgets(
      'programme boundary updates locally; hidden tabs and disposed pages stop their clock',
      (tester) async {
    var now = DateTime.utc(2026, 11, 20, 10, 0);
    final boundary = now.add(const Duration(seconds: 10));
    Widget app(bool active) => MaterialApp(
        home: ClockProbe(
            key: const ValueKey('clock'),
            now: () => now,
            boundary: boundary,
            active: active));
    await tester.pumpWidget(app(true));
    expect(find.text('revision:0'), findsOneWidget);
    now = boundary;
    await tester.pump(const Duration(milliseconds: 10020));
    expect(find.text('revision:1'), findsOneWidget);
    await tester.pumpWidget(app(false));
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('revision:1'), findsOneWidget);
    await tester.pumpWidget(app(true));
    expect(find.text('revision:2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'backgrounding suspends ticks and resuming refreshes cached labels',
      (tester) async {
    var now = DateTime.utc(2026, 11, 20, 10, 0);
    await tester.pumpWidget(
        MaterialApp(home: ClockProbe(now: () => now, boundary: null)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('revision:0'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('revision:1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
