import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analytics_service.dart';
import 'screens/ios_player_page.dart';

class NativePlayer {
  static const MethodChannel _channel = MethodChannel(
    'football_stream/native_player',
  );
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

      await AnalyticsService.capture(event, properties: properties);
    });
  }

  static Future<void> open({
    BuildContext? context,
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
    String? matchId,
  }) async {
    if (Platform.isIOS) {
      if (context == null || !context.mounted) {
        throw StateError(
          'An active screen is required to open the iOS player.',
        );
      }
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => IOSPlayerPage(
              sources: sources,
              selectedIndex: selectedIndex,
              title: title ?? 'Football Live',
              matchId: matchId ?? '',
            ),
          ),
        ),
      );
      return;
    }
    _ensureEventHandler();
    await _channel.invokeMethod<void>('openPlayer', {
      'sourcesJson': jsonEncode(sources),
      'selectedIndex': selectedIndex,
      'title': title ?? 'Football Live',
      'matchId': matchId ?? '',
    });
  }
}
