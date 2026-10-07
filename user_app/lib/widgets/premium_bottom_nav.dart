import 'package:flutter/material.dart';

class PremiumBottomNav extends StatelessWidget {
  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, IconData selected, String label})>[
    (
      icon: Icons.live_tv_outlined,
      selected: Icons.live_tv_rounded,
      label: 'Live',
    ),
    (
      icon: Icons.sports_soccer_outlined,
      selected: Icons.sports_soccer_rounded,
      label: 'Soco',
    ),
    (
      icon: Icons.sensors_outlined,
      selected: Icons.sensors_rounded,
      label: 'YYZB',
    ),
    (
      icon: Icons.language_outlined,
      selected: Icons.language_rounded,
      label: 'Fawa',
    ),
    (
      icon: Icons.tv_outlined,
      selected: Icons.tv_rounded,
      label: 'ColaTV',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .98),
        border: Border(
          top: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .35),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .10),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = selectedIndex == index;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: InkResponse(
                    onTap: () => onSelected(index),
                    containedInkWell: true,
                    highlightShape: BoxShape.rectangle,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primary.withValues(alpha: .13)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              selected ? item.selected : item.icon,
                              size: 21,
                              color: selected
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight:
                                    selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
