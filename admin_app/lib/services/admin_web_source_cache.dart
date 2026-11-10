import 'dart:async';

import 'package:flutter/foundation.dart';

/// Web-only, in-memory cache for authenticated Admin source catalogues.
/// Never persists private provider data or stream credentials to browser disk.
class AdminSourceUiState {
  const AdminSourceUiState({
    this.query = '',
    this.dayFilter = 'today',
    this.availableOnly = false,
    this.scrollOffset = 0,
  });

  final String query;
  final String dayFilter;
  final bool availableOnly;
  final double scrollOffset;
}

class _SourceSnapshot {
  _SourceSnapshot(this.rows, this.savedAt);
  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;
}

class AdminWebSourceCache {
  AdminWebSourceCache._();

  static const ttl = Duration(minutes: 5);
  static String? _userId;
  static int _sessionEpoch = 0;
  // Captured by mounted source widgets to reject post-logout responses and
  // avoid saving old form state into the next account's cache.
  static int get sessionGeneration => _sessionEpoch;
  static final Map<String, _SourceSnapshot> _entries = {};
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};
  static final Map<String, AdminSourceUiState> _ui = {};

  static void bindUser(String? userId) {
    if (!kIsWeb || _userId == userId) return;
    clear();
    _userId = userId;
  }

  /// Also invalidates the generation captured by any still-running request.
  static void clear() {
    _sessionEpoch++;
    _entries.clear();
    _inFlight.clear();
    _ui.clear();
    _userId = null;
  }

  static List<Map<String, dynamic>>? rows(String provider) =>
      kIsWeb && _userId != null ? _entries[provider]?.rows : null;

  static bool fresh(String provider, {DateTime? at}) {
    if (!kIsWeb || _userId == null) return false;
    final entry = _entries[provider];
    return entry != null &&
        (at ?? DateTime.now()).difference(entry.savedAt) < ttl;
  }

  static AdminSourceUiState ui(String provider) =>
      kIsWeb && _userId != null
          ? _ui[provider] ?? const AdminSourceUiState()
          : const AdminSourceUiState();

  static void saveUi(String provider, AdminSourceUiState value) {
    if (kIsWeb && _userId != null) _ui[provider] = value;
  }

  static void invalidate(String provider) {
    if (!kIsWeb) return;
    _entries.remove(provider);
    _ui.remove(provider);
  }

  /// Successful empty lists supersede older fixtures; errors retain last good.
  /// One provider network call survives opening/closing its widget.
  static Future<List<Map<String, dynamic>>> load(
    String provider,
    Future<List<Map<String, dynamic>>> Function() fetch, {
    bool force = false,
  }) {
    if (!kIsWeb || _userId == null) return fetch();
    if (!force && fresh(provider)) {
      return Future.value(_entries[provider]!.rows);
    }
    final inFlight = _inFlight[provider];
    if (inFlight != null) return inFlight;

    final owner = _userId;
    final epoch = _sessionEpoch;
    final operation = Future<List<Map<String, dynamic>>>.sync(() async {
      final result = await fetch();
      if (_userId == owner && _sessionEpoch == epoch) {
        _entries[provider] = _SourceSnapshot(result, DateTime.now());
      }
      return result;
    });
    _inFlight[provider] = operation;
    unawaited(operation.then<void>((_) {
      if (identical(_inFlight[provider], operation)) _inFlight.remove(provider);
    }, onError: (Object _, StackTrace __) {
      if (identical(_inFlight[provider], operation)) _inFlight.remove(provider);
    }));
    return operation;
  }
}
