import 'dart:async';
import 'package:flutter/foundation.dart';

/// Preserve successful data during refreshes and temporary network failures.
/// An empty successful response still replaces the previous data.
class LiveFeedController<T> extends ChangeNotifier {
  LiveFeedController(this.load, {T? initialData}) : _data = initialData;

  final Future<T> Function() load;
  T? _data;
  Object? _error;
  Future<void>? _pending;
  bool _loading = false;
  bool _disposed = false;

  T? get data => _data;
  Object? get error => _error;
  bool get hasData => _data != null;
  bool get loading => _loading;

  /// Paint a persisted snapshot without waiting for the current API request.
  /// Never replace an authoritative successful response, even an empty list.
  void seedIfMissing(T snapshot) {
    if (_disposed || _data != null) return;
    _data = snapshot;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;

    final completed = Completer<void>();
    _pending = completed.future;
    _loading = true;
    _error = null;
    notifyListeners();
    unawaited(() async {
      try {
        final next = await load();
        if (!_disposed) _data = next;
      } catch (error) {
        if (!_disposed) _error = error;
      } finally {
        _pending = null;
        _loading = false;
        if (!_disposed) notifyListeners();
        completed.complete();
      }
    }());
    return completed.future;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
