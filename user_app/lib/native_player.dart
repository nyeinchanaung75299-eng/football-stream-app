import 'dart:convert';
import 'package:flutter/services.dart';

class NativePlayer {
  static const MethodChannel _channel =
      MethodChannel('football_stream/native_player');

  static Future<void> open({
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
  }) async {
    await _channel.invokeMethod<void>('openPlayer', {
      'sourcesJson': jsonEncode(sources),
      'selectedIndex': selectedIndex,
      'title': title ?? 'Football Live',
    });
  }
}
