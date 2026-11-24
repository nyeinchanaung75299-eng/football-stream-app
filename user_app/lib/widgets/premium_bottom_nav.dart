import 'package:flutter/material.dart';

/// Five uncluttered tabs; all eight original routes remain reachable.
/// Source choices retain their existing onSelected indices and route identity.
class PremiumBottomNav extends StatelessWidget {
  const PremiumBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, IconData selected, String label, int route})>[
    (icon: Icons.live_tv_outlined, selected: Icons.live_tv, label: 'Live', route: 0),
    (icon: Icons.play_circle_outline, selected: Icons.play_circle,
      label: 'Live 2', route: 1),
    (icon: Icons.grid_view_outlined, selected: Icons.grid_view,
      label: 'Sources', route: -1),
    (icon: Icons.tv_outlined, selected: Icons.tv,
      label: 'Channels', route: 6),
    (icon: Icons.video_library_outlined, selected: Icons.video_library,
      label: 'HL', route: 7),
  ];
  static const _sources = <({String label, IconData icon, int route})>[
    (label: 'Soco', icon: Icons.sports_soccer_outlined, route: 2),
    (label: 'YYZB', icon: Icons.sensors_outlined, route: 3),
    (label: 'ColaTV', icon: Icons.tv_outlined, route: 4),
    (label: 'Fawa', icon: Icons.language_outlined, route: 5),
  ];

  int get _selectedSlot {
    if (selectedIndex >= 2 && selectedIndex <= 5) return 2;
    if (selectedIndex == 6) return 3;
    if (selectedIndex == 7) return 4;
    return selectedIndex;
  }

  void _select(BuildContext context, int slot) {
    if (slot != 2) {
      onSelected(_items[slot].route);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Football sources',
              style: Theme.of(sheet).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final item in _sources)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              selected: selectedIndex == item.route,
              trailing: selectedIndex == item.route
                  ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(sheet);
                onSelected(item.route);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .98),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
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
              final selected = _selectedSlot == index;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: InkResponse(
                    onTap: () => _select(context, index),
                    containedInkWell: true,
                    highlightShape: BoxShape.rectangle,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
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
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.1,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
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
