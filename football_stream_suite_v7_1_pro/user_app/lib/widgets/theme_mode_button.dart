import 'package:flutter/material.dart';
import '../theme_controller.dart';

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.instance;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final icon = switch (controller.mode) {
          ThemeMode.light => Icons.light_mode_rounded,
          ThemeMode.dark => Icons.dark_mode_rounded,
          ThemeMode.system => Icons.brightness_auto_rounded,
        };

        return PopupMenuButton<ThemeMode>(
          tooltip: 'Theme',
          icon: Icon(icon),
          onSelected: controller.setMode,
          itemBuilder: (_) => [
            _item(
              ThemeMode.system,
              Icons.brightness_auto_rounded,
              'System',
              controller.mode,
            ),
            _item(
              ThemeMode.light,
              Icons.light_mode_rounded,
              'Light',
              controller.mode,
            ),
            _item(
              ThemeMode.dark,
              Icons.dark_mode_rounded,
              'Dark',
              controller.mode,
            ),
          ],
        );
      },
    );
  }

  PopupMenuItem<ThemeMode> _item(
    ThemeMode value,
    IconData icon,
    String label,
    ThemeMode current,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (current == value) const Icon(Icons.check_rounded, size: 20),
        ],
      ),
    );
  }
}
