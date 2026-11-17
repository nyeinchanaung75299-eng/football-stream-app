import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/source_room_status.dart';

void main() {
  test('CricHD Link 2 stays UNKNOWN on denied or unverified player', () {
    expect(sourceRoomStatusFromLines(
      provider: 'crichd', isLive: false, hasHealthy: false, lineCount: 0,
    ), 'unknown');
    expect(sourceRoomStatusFromLines(
      provider: 'crichd', isLive: false, hasHealthy: false, lineCount: 1,
    ), 'unknown');
    expect(sourceRoomStatusFromLines(
      provider: 'crichd', isLive: false, hasHealthy: true, lineCount: 1,
    ), 'ready');
  });

  test('Roxie never calls unverified candidates OFFLINE', () {
    for (final provider in ['roxie']) {
      expect(sourceRoomStatusFromLines(
        provider: provider, isLive: false, hasHealthy: false, lineCount: 0,
      ), 'unknown');
      expect(sourceRoomStatusFromLines(
        provider: provider, isLive: false, hasHealthy: false, lineCount: 2,
      ), 'unknown');
    }
  });

  test('Existing Soco, YYZB, Fawa, Cola and Arena semantics are unchanged', () {
    for (final provider in ['soco', 'yyzb', 'fawa', 'cola', 'arena']) {
      expect(sourceRoomStatusFromLines(
        provider: provider, isLive: false, hasHealthy: false, lineCount: 0,
      ), 'offline');
      expect(sourceRoomStatusFromLines(
        provider: provider, isLive: false, hasHealthy: false, lineCount: 1,
      ), 'ready');
      expect(sourceRoomStatusFromLines(
        provider: provider, isLive: true, hasHealthy: false, lineCount: 0,
      ), 'live');
    }
  });
}
