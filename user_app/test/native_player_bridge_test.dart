import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/native_player_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('football_stream/native_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const sources = <Map<String, dynamic>>[
    {'id': 'primary', 'url': 'https://source.example.invalid/live.m3u8'},
    {'id': 'backup', 'url': 'https://backup.example.invalid/live.m3u8'},
  ];

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'a fast backup update retries while Android creates the matching activity',
    () async {
      var updates = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'openPlayer') {
          expect((call.arguments as Map)['sessionId'], 'opening-session');
          return null;
        }
        expect(call.method, 'updatePlayerSources');
        expect((call.arguments as Map)['sessionId'], 'opening-session');
        updates += 1;
        return updates == 3;
      });
      await NativePlayer.open(
        sources: sources.take(1).toList(),
        selectedIndex: 0,
        sessionId: 'opening-session',
      );
      await NativePlayer.updateSources(
        sources: sources,
        sessionId: 'opening-session',
      );
      expect(updates, 3);
    },
  );

  test(
    'opening a new player cancels a pending old-session backup retry',
    () async {
      final firstUpdate = Completer<void>();
      var oldUpdates = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'openPlayer') return null;
        oldUpdates += 1;
        if (!firstUpdate.isCompleted) firstUpdate.complete();
        return false;
      });
      await NativePlayer.open(
        sources: sources.take(1).toList(),
        selectedIndex: 0,
        sessionId: 'old-session',
      );
      final pending = NativePlayer.updateSources(
        sources: sources,
        sessionId: 'old-session',
      );
      await firstUpdate.future;
      await NativePlayer.open(
        sources: sources.take(1).toList(),
        selectedIndex: 0,
        sessionId: 'new-session',
      );
      await pending;
      expect(
        oldUpdates,
        1,
        reason: 'A delayed backup must never cross player sessions',
      );
      await NativePlayer.updateSources(
        sources: sources,
        sessionId: 'old-session',
      );
      expect(oldUpdates, 1);
    },
  );
}
