import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  static const _storageKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  int _modeVersion = 0;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final version = _modeVersion;
    final prefs = await SharedPreferences.getInstance();
    if (version != _modeVersion) return;
    final saved = prefs.getString(_storageKey);
    _mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _modeVersion += 1;
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}
