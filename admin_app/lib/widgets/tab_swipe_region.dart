import 'package:flutter/material.dart';

/// Adjacent tabs only. Nested horizontal scrollables and text editing retain
/// their normal gesture handling; the keyboard disables tab swipes.
class TabSwipeRegion extends StatefulWidget {
  const TabSwipeRegion({super.key, required this.index, required this.count,
    required this.onSelected, required this.child, this.enabled = true});
  final int index, count;
  final ValueChanged<int> onSelected;
  final Widget child;
  final bool enabled;

  @override
  State<TabSwipeRegion> createState() => _TabSwipeRegionState();
}

class _TabSwipeRegionState extends State<TabSwipeRegion> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && MediaQuery.viewInsetsOf(context).bottom == 0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: enabled ? (_) => _distance = 0 : null,
      onHorizontalDragUpdate: enabled ? (event) {
        _distance += event.primaryDelta ?? 0;
      } : null,
      onHorizontalDragCancel: enabled ? () => _distance = 0 : null,
      onHorizontalDragEnd: enabled ? (event) {
        final delta = _distance;
        _distance = 0;
        if (ModalRoute.of(context)?.isCurrent == false ||
            MediaQuery.viewInsetsOf(context).bottom > 0) return;
        final velocity = event.primaryVelocity ?? 0;
        if (delta.abs() < 48 && (delta.abs() < 18 || velocity.abs() < 420)) return;
        final next = widget.index + (delta < 0 ? 1 : -1);
        if (next >= 0 && next < widget.count) widget.onSelected(next);
      } : null,
      child: widget.child,
    );
  }
}
