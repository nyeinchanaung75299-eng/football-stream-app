import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/admin_web_source_cache.dart';

void main() {
  setUp(AdminWebSourceCache.clear);
  tearDown(AdminWebSourceCache.clear);

  test('Web: revisiting Soco uses one successful provider fetch', () async {
    AdminWebSourceCache.bindUser('admin-a');
    var calls = 0;
    Future<List<Map<String, dynamic>>> fetch() async {
      calls++;
      return [{'source': 'soco', 'home_team': 'Arsenal'}];
    }
    await AdminWebSourceCache.load('soco', fetch);
    await AdminWebSourceCache.load('soco', fetch);
    expect(calls, kIsWeb ? 1 : 2);
    if (kIsWeb) {
      expect(AdminWebSourceCache.rows('soco')!.first['home_team'], 'Arsenal');
      AdminWebSourceCache.saveUi('soco', const AdminSourceUiState(
        query: 'arsenal', dayFilter: 'all', scrollOffset: 240,
      ));
      expect(AdminWebSourceCache.ui('soco').query, 'arsenal');
      expect(AdminWebSourceCache.ui('soco').scrollOffset, 240);
    }
  });

  test('Web: concurrent provider loads share one in-flight request', () async {
    AdminWebSourceCache.bindUser('admin-a');
    final signal = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    Future<List<Map<String, dynamic>>> fetch() {
      calls++;
      return signal.future;
    }
    final first = AdminWebSourceCache.load('soco', fetch, force: true);
    final second = AdminWebSourceCache.load('soco', fetch, force: true);
    expect(calls, kIsWeb ? 1 : 2);
    if (kIsWeb) expect(identical(first, second), isTrue);
    signal.complete([{'id': 'one'}]);
    await Future.wait([first, second]);
  });

  test('Web: empty success deletes old rows, failure leaves last good', () async {
    AdminWebSourceCache.bindUser('admin-a');
    await AdminWebSourceCache.load(
      'soco', () async => [{'id': 'old'}], force: true);
    try {
      await AdminWebSourceCache.load(
        'soco', () => throw StateError('offline'), force: true);
      fail('Expected failure');
    } on StateError {
      // A failed refresh must not evict its last successful result.
    }
    if (kIsWeb) expect(AdminWebSourceCache.rows('soco')!.length, 1);
    await AdminWebSourceCache.load('soco', () async => [], force: true);
    if (kIsWeb) expect(AdminWebSourceCache.rows('soco'), isEmpty);
  });

  test('Web: logout and account change isolate cached provider state', () async {
    AdminWebSourceCache.bindUser('admin-a');
    await AdminWebSourceCache.load('yyzb', () async => [
      {'id': 'private-admin-a'},
    ], force: true);
    AdminWebSourceCache.bindUser(null);
    AdminWebSourceCache.bindUser('admin-b');
    expect(AdminWebSourceCache.rows('yyzb'), isNull);
    expect(AdminWebSourceCache.ui('yyzb').query, isEmpty);
  });

  test('Web: logout then same-user login rejects prior session results', () async {
    AdminWebSourceCache.bindUser('admin-a');
    final originalGeneration = AdminWebSourceCache.sessionGeneration;
    final pendingResult = Completer<List<Map<String, dynamic>>>();
    final pending = AdminWebSourceCache.load(
      'soco', () => pendingResult.future, force: true);

    AdminWebSourceCache.bindUser(null);
    AdminWebSourceCache.bindUser('admin-a');
    if (kIsWeb) {
      expect(AdminWebSourceCache.sessionGeneration,
          greaterThan(originalGeneration));
    }

    pendingResult.complete([{'id': 'previous-session-private-row'}]);
    await pending;
    expect(AdminWebSourceCache.rows('soco'), isNull);
  });

  test('Web: an old account in-flight request cannot populate next user cache',
      () async {
    AdminWebSourceCache.bindUser('admin-a');
    final old = Completer<List<Map<String, dynamic>>>();
    final pending = AdminWebSourceCache.load(
      'fawa', () => old.future, force: true);
    AdminWebSourceCache.bindUser('admin-b');
    old.complete([{'id': 'private-admin-a'}]);
    await pending;
    expect(AdminWebSourceCache.rows('fawa'), isNull);
  });
}
