import 'dart:async';

/// In-memory public Viewer tab cache. Stores successful responses (including
/// authoritative empty lists) and preserves per-tab UI state across the
/// existing pushReplacement navigation. No stream credentials are persisted.
class ViewerSourceUiState {
  const ViewerSourceUiState({
    this.query = '',
    this.league,
    this.todayOnly = false,
    this.scrollOffset = 0,
  });

  final String query;
  final String? league;
  final bool todayOnly;
  final double scrollOffset;
}

class ViewerChannelsUiState {
  const ViewerChannelsUiState({
    this.search = '',
    this.group = 'All',
    this.matchId,
    this.libraryFilter = 'all',
    this.scrollOffset = 0,
  });

  final String search;
  final String group;
  final String? matchId;
  final String libraryFilter;
  final double scrollOffset;
}

class _TabResult {
  const _TabResult(this.rows, this.fetchedAt);
  final List<Map<String, dynamic>> rows;
  final DateTime fetchedAt;
}

class ViewerTabCache {
  ViewerTabCache._();

  static const sourceTtl = Duration(seconds: 75);
  static const channelTtl = Duration(minutes: 4);

  static final Map<String, _TabResult> _sources = {};
  static final Map<String, Future<List<Map<String, dynamic>>>> _sourceInFlight = {};
  static final Map<String, ViewerSourceUiState> _sourceUi = {};

  static _TabResult? _channels;
  static Future<List<Map<String, dynamic>>>? _channelsInFlight;
  static ViewerChannelsUiState channelUi = const ViewerChannelsUiState();

  static List<Map<String, dynamic>>? sourceRows(String source) =>
      _sources[source]?.rows;

  static bool sourceFresh(String source, {DateTime? now}) {
    final entry = _sources[source];
    return entry != null &&
        (now ?? DateTime.now()).difference(entry.fetchedAt) < sourceTtl;
  }

  static ViewerSourceUiState sourceUi(String source) =>
      _sourceUi[source] ?? const ViewerSourceUiState();

  static void saveSourceUi(String source, ViewerSourceUiState ui) =>
      _sourceUi[source] = ui;

  /// A refresh in flight is shared, including when the user changes tabs and
  /// returns quickly. A successful [] replaces previous rows; failures do not.
  static Future<List<Map<String, dynamic>>> loadSource(
    String source,
    Future<List<Map<String, dynamic>>> Function() fetch, {
    bool force = false,
  }) {
    final previous = _sources[source];
    if (!force && sourceFresh(source) && previous != null) {
      return Future.value(previous.rows);
    }
    final pending = _sourceInFlight[source];
    if (pending != null) return pending;
    final operation = Future<List<Map<String, dynamic>>>(() async {
      final next = await fetch();
      _sources[source] = _TabResult(next, DateTime.now());
      return next;
    });
    _sourceInFlight[source] = operation;
    unawaited(operation.then<void>((_) {
      if (identical(_sourceInFlight[source], operation)) {
        _sourceInFlight.remove(source);
      }
    }, onError: (Object _, StackTrace __) {
      if (identical(_sourceInFlight[source], operation)) {
        _sourceInFlight.remove(source);
      }
    }));
    return operation;
  }

  static List<Map<String, dynamic>>? get channelRows => _channels?.rows;

  static bool channelsFresh({DateTime? now}) {
    final entry = _channels;
    return entry != null &&
        (now ?? DateTime.now()).difference(entry.fetchedAt) < channelTtl;
  }

  static Future<List<Map<String, dynamic>>> loadChannels(
    Future<List<Map<String, dynamic>>> Function() fetch, {
    bool force = false,
  }) {
    if (!force && channelsFresh() && _channels != null) {
      return Future.value(_channels!.rows);
    }
    final pending = _channelsInFlight;
    if (pending != null) return pending;
    final operation = Future<List<Map<String, dynamic>>>(() async {
      final next = await fetch();
      _channels = _TabResult(next, DateTime.now());
      return next;
    });
    _channelsInFlight = operation;
    unawaited(operation.then<void>((_) {
      if (identical(_channelsInFlight, operation)) _channelsInFlight = null;
    }, onError: (Object _, StackTrace __) {
      if (identical(_channelsInFlight, operation)) _channelsInFlight = null;
    }));
    return operation;
  }

  /// Useful when an admin-side event is known to change the public catalog.
  static void invalidateChannels() => _channels = null;
}
