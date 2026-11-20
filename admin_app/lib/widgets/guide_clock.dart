import 'dart:async';
import 'package:flutter/widgets.dart';

/// Recompute cached guide labels at time boundaries without a network poll.
/// Hidden tabs and backgrounded apps do not keep rebuilding their guide lists.
mixin GuideClock<T extends StatefulWidget> on State<T> {
  Timer? _guideClockTimer;
  AppLifecycleListener? _guideLifecycle;
  bool _guideForeground = true;
  int guideClockRevision = 0;
  bool _wasActive = false;
  bool get guideClockActive;
  DateTime get guideNow => DateTime.now().toUtc();
  DateTime? nextGuideBoundary(DateTime now) => null;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _guideForeground = state == null || state == AppLifecycleState.resumed;
    _guideLifecycle = AppLifecycleListener(onStateChange: (state) {
      _guideForeground = state == AppLifecycleState.resumed;
      if (_guideForeground && guideClockActive && mounted) {
        setState(() => guideClockRevision++);
      }
      refreshGuideClock();
    });
    _wasActive = guideClockActive;
    refreshGuideClock();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tab re-entry must also catch boundaries crossed while it was hidden.
    if (guideClockActive && !_wasActive) guideClockRevision++;
    _wasActive = guideClockActive;
    refreshGuideClock();
  }

  void refreshGuideClock() {
    _guideClockTimer?.cancel();
    if (!mounted || !_guideForeground || !guideClockActive) return;
    final now = guideNow;
    var next = DateTime.fromMillisecondsSinceEpoch(
        (now.millisecondsSinceEpoch ~/ 60000 + 1) * 60000,
        isUtc: true);
    final boundary = nextGuideBoundary(now);
    if (boundary != null && boundary.isAfter(now) && boundary.isBefore(next))
      next = boundary;
    _guideClockTimer =
        Timer(next.difference(now) + const Duration(milliseconds: 20), () {
      if (!mounted || !_guideForeground || !guideClockActive) return;
      setState(() => guideClockRevision++);
      refreshGuideClock();
    });
  }

  @override
  void dispose() {
    _guideClockTimer?.cancel();
    _guideLifecycle?.dispose();
    super.dispose();
  }
}
