import 'dart:async';

/// Small process-local cache for public programme metadata.
///
/// Deduplicates simultaneous channel-screen openings and avoids refetching the
/// same day's guide when switching between Home and Channels. Protected media
/// URLs, auth sessions and private stream metadata must never use this cache.
class PublicGuideCache<T> {
  PublicGuideCache({this.ttl = const Duration(minutes: 2)});

  final Duration ttl;
  Future<T>? _cached;
  String? _key;
  DateTime? _loadedAt;
  int _generation = 0;

  Future<T> load(
    String key,
    Future<T> Function() fetch, {
    bool refresh = false,
  }) {
    final loaded = _loadedAt;
    if (!refresh && _cached != null && _key == key &&
        (loaded == null ||
            (DateTime.now().difference(loaded) >= Duration.zero &&
                DateTime.now().difference(loaded) < ttl))) {
      return _cached!;
    }

    final generation = ++_generation;
    _key = key;
    _loadedAt = null;
    final future = Future<T>.sync(fetch);
    _cached = future;
    unawaited(future.then((_) {
      if (_generation == generation) _loadedAt = DateTime.now();
    }, onError: (Object _, StackTrace __) {
      // Never remember failures. Allow the next screen open to retry.
      if (_generation == generation) {
        _cached = null;
        _key = null;
        _loadedAt = null;
      }
    }));
    return future;
  }
}
