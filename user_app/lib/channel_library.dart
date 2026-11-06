import 'package:shared_preferences/shared_preferences.dart';

/// Persist only channel IDs, never playback URLs, headers, or credentials.
class ChannelLibrary {
  ChannelLibrary();
  static final instance = ChannelLibrary();
  final Set<String> favorites = {};
  final List<String> recent = [];
  Future<void>? _loading;
  Future<void> _saving = Future.value();

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      favorites.addAll(prefs.getStringList('nca_channel_favorites_v1') ?? []);
      recent.addAll((prefs.getStringList('nca_channel_recent_v1') ?? []).take(30));
    } catch (_) {
      _loading = null;
    }
  }

  Future<void> toggleFavorite(String id) async {
    await load();
    if (!favorites.remove(id)) favorites.add(id);
    await _save();
  }

  Future<void> recordRecent(String id) async {
    await load();
    recent.remove(id);
    recent.insert(0, id);
    if (recent.length > 30) recent.removeRange(30, recent.length);
    await _save();
  }

  Future<void> _save() {
    final favoritesSnapshot = favorites.toList();
    final recentSnapshot = recent.toList();
    _saving = _saving.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('nca_channel_favorites_v1', favoritesSnapshot);
      await prefs.setStringList('nca_channel_recent_v1', recentSnapshot);
    });
    return _saving;
  }
}
