import 'dart:async';

import 'package:flutter/foundation.dart';

typedef SourceLines = List<Map<String, dynamic>>;

/// Publishes the first usable anchor without waiting for unrelated anchors.
/// Later batches append, so a line already shown keeps its index and identity.
class SourceLineLoader extends ChangeNotifier {
  SourceLineLoader({
    required List<Future<SourceLines> Function()> anchors,
    required Comparator<Map<String, dynamic>> compare,
  }) : _anchors = anchors,
       _compare = compare;

  final List<Future<SourceLines> Function()> _anchors;
  final Comparator<Map<String, dynamic>> _compare;
  final _first = Completer<SourceLines?>();
  final _settled = Completer<SourceLines?>();
  final _rows = <Map<String, dynamic>>[];
  final _seen = <String>{};
  var _active = true;
  var _started = false;
  var _remaining = 0;
  var _succeeded = false;
  Object? _lastError;
  StackTrace? _lastStack;

  SourceLines get rows => List.unmodifiable(_rows);
  bool get loading => _active && _remaining > 0;
  bool get cancelled => !_active;
  Future<SourceLines?> get firstUsable => _first.future;
  Future<SourceLines?> get settled => _settled.future;

  void start() {
    if (_started || !_active) return;
    _started = true;
    _remaining = _anchors.length;
    if (_remaining == 0) {
      _finish();
      return;
    }
    for (final load in _anchors) {
      unawaited(_load(load));
    }
  }

  Future<void> _load(Future<SourceLines> Function() load) async {
    try {
      final batch = await load();
      if (!_active) return;
      _succeeded = true;
      final additions = <Map<String, dynamic>>[];
      for (final row in batch) {
        final url = row['stream_url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;
        final id = row['id']?.toString() ?? '';
        final key = id.isNotEmpty ? 'id:$id' : 'url:$url';
        if (_seen.add(key)) additions.add(row);
      }
      additions.sort(_compare);
      _rows.addAll(additions);
      if (_rows.isNotEmpty && !_first.isCompleted) {
        _first.complete(rows);
      }
    } catch (error, stack) {
      if (!_active) return;
      _lastError = error;
      _lastStack = stack;
    } finally {
      if (_active) {
        _remaining--;
        if (_remaining == 0) _finish();
        notifyListeners();
      }
    }
  }

  void _finish() {
    if (!_first.isCompleted) {
      if (!_succeeded && _lastError != null) {
        _first.completeError(_lastError!, _lastStack);
      } else {
        // Every successful response was empty: preserve that result rather
        // than treating it as a reason to revive cached/mirrored lines.
        _first.complete(rows);
      }
    }
    if (!_settled.isCompleted) _settled.complete(rows);
  }

  /// HTTP requests retain their existing bounded timeouts. Cancelling stops
  /// publication immediately and safely ignores requests that finish later.
  void cancel() {
    if (!_active) return;
    _active = false;
    if (!_first.isCompleted) _first.complete(null);
    if (!_settled.isCompleted) _settled.complete(null);
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}
