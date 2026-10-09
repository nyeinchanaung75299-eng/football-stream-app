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
  static String _iosSessionId = '';
  static String _androidSessionId = '';
  static List<Map<String, dynamic>>? _iosSources;
  static ValueNotifier<int>? _iosSourceUpdates;

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
    String? sessionId,
  }) async {
    if (Platform.isIOS) {
      if (context == null || !context.mounted) {
        throw StateError(
          'An active screen is required to open the iOS player.',
        );
      }
      final activeSources = List<Map<String, dynamic>>.of(sources);
      final sourceUpdates = ValueNotifier<int>(0);
      _iosSessionId = sessionId ?? '';
      _iosSources = activeSources;
      _iosSourceUpdates = sourceUpdates;
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => IOSPlayerPage(
              sources: activeSources,
              sourceUpdates: sourceUpdates,
              onClosed: () {
                if (identical(_iosSourceUpdates, sourceUpdates)) {
                  _iosSessionId = '';
                  _iosSources = null;
                  _iosSourceUpdates = null;
                }
                sourceUpdates.dispose();
              },
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
    _androidSessionId = sessionId ?? '';
    await _channel.invokeMethod<void>('openPlayer', {
      'sourcesJson': jsonEncode(sources),
      'selectedIndex': selectedIndex,
      'title': title ?? 'Football Live',
      'matchId': matchId ?? '',
      'sessionId': sessionId ?? '',
    });
  }

  static Future<void> updateSources({
    required List<Map<String, dynamic>> sources,
    required String sessionId,
  }) async {
    if (sessionId.isEmpty) return;
    if (Platform.isIOS) {
      final active = _iosSources;
      final updates = _iosSourceUpdates;
      if (_iosSessionId != sessionId ||
          active == null ||
          updates == null ||
          sources.length <= active.length)
        return;
      for (var i = 0; i < active.length; i++) {
        final old = active[i], next = sources[i];
        if (old['id'] != null && next['id'] != null
            ? old['id'].toString() != next['id'].toString()
            : old['url'] != next['url'])
          return;
      }
      active.addAll(sources.skip(active.length));
      updates.value += 1;
      return;
    }
    final payload = <String, Object>{
      'sourcesJson': jsonEncode(sources),
      'sessionId': sessionId,
    };
    // A very fast backup can arrive while Android is still creating the player
    // Activity. Retry briefly without ever delivering to a newer session.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_androidSessionId != sessionId) return;
      final accepted = await _channel.invokeMethod<bool>(
        'updatePlayerSources',
        payload,
      );
      if (accepted == true) return;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}
