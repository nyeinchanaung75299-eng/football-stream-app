import 'package:flutter/material.dart';

/// All eight routes remain visible in one row at every supported width.
class PremiumBottomNav extends StatelessWidget {
  const PremiumBottomNav({super.key, required this.selectedIndex, required this.onSelected});
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  static const _items = <({IconData icon, IconData selected, String label})>[
    (icon: Icons.live_tv_outlined, selected: Icons.live_tv, label: 'Live'),
    (icon: Icons.play_circle_outline, selected: Icons.play_circle, label: 'Live 2'),
    (icon: Icons.sports_soccer_outlined, selected: Icons.sports_soccer, label: 'Soco'),
    (icon: Icons.sensors_outlined, selected: Icons.sensors, label: 'YYZB'),
    (icon: Icons.tv_outlined, selected: Icons.tv, label: 'ColaTV'),
    (icon: Icons.language_outlined, selected: Icons.language, label: 'Fawa'),
    (icon: Icons.tv_outlined, selected: Icons.tv, label: 'Channels'),
    (icon: Icons.video_library_outlined, selected: Icons.video_library, label: 'HL'),
  ];
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SafeArea(top: false,
        child: SizedBox(height: 64, child: Row(
          children: List.generate(_items.length, (index) {
            final item = _items[index];
            final selected = selectedIndex == index;
            final color = selected ? colors.primary : colors.onSurfaceVariant;
            return Expanded(child: Semantics(
              button: true, selected: selected, label: item.label,
              child: InkWell(onTap: () => onSelected(index),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: selected ? colors.primary.withValues(alpha: .13) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(selected ? item.selected : item.icon, size: 21, color: color),
                      const SizedBox(height: 4),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FittedBox(fit: BoxFit.scaleDown,
                          child: Text(item.label, maxLines: 1, style: TextStyle(
                            fontSize: 11, height: 1.1, color: color,
                            fontWeight: selected ? FontWeight.w800 : FontWeight.w600)))),
                    ]),
                  ),
                ),
              ),
            ));
          }),
        )),
      ),
    );
  }
}
