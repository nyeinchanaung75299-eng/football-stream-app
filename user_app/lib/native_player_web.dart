import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('openFootballPlayer')
external void _openFootballPlayer(
  JSString sourcesJson,
  JSNumber selectedIndex,
  JSString title,
  JSString matchId,
);

class NativePlayer {
  static Future<void> open({
    BuildContext? context,
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
    String? matchId,
  }) async {
    _openFootballPlayer(
      jsonEncode(sources).toJS,
      selectedIndex.toJS,
      (title ?? 'Football Live').toJS,
      (matchId ?? '').toJS,
    );
  }
}
