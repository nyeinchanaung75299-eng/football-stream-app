import 'dart:convert';
import 'package:flutter/services.dart';

import 'analytics_service.dart';

class NativePlayer {
  static const MethodChannel _channel =
      MethodChannel('football_stream/native_player');
  static bool _eventHandlerInstalled = false;

  static void _ensureEventHandler() {
    if (_eventHandlerInstalled) return;
    _eventHandlerInstalled = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'playerEvent') return;

      final raw = call.arguments;
      if (raw is! Map) return;

      final event = raw['event']?.toString().trim() ?? '';
      if (event.isEmpty) return;

      final properties = <String, Object>{};
      final rawProperties = raw['properties'];
      if (rawProperties is Map) {
        rawProperties.forEach((key, value) {
          if (key != null && value != null) {
            properties[key.toString()] = value as Object;
          }
        });
      }

      await AnalyticsService.capture(
        event,
        properties: properties,
      );
    });
  }

  static Future<void> open({
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
  }) async {
    _ensureEventHandler();
    await _channel.invokeMethod<void>('openPlayer', {
      'sourcesJson': jsonEncode(sources),
      'selectedIndex': selectedIndex,
      'title': title ?? 'Football Live',
    });
  }
}
