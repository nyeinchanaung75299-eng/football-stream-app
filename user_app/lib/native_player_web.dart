import 'dart:convert';
import 'dart:js_interop';

@JS('openFootballPlayer')
external void _openFootballPlayer(
  JSString sourcesJson,
  JSNumber selectedIndex,
  JSString title,
);

class NativePlayer {
  static Future<void> open({
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
  }) async {
    _openFootballPlayer(
      jsonEncode(sources).toJS,
      selectedIndex.toJS,
      (title ?? 'Football Live').toJS,
    );
  }
}
