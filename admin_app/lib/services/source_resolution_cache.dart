import 'dart:async';
import 'dart:convert';

/// Session-memory only, bounded, never writes URLs/credentials to disk.
class SourceResolutionCache {
  static final _values =
      <String, ({Map<String, dynamic> value, DateTime at})>{};
  static final _inFlight = <String, Future<Map<String, dynamic>>>{};
  static String? _owner;
  static int _epoch = 0;
  static void bind(String? owner) {
    if (_owner != owner) {
      clear();
      _owner = owner;
    }
  }

  static void clear() {
    _epoch++;
    _values.clear();
    _inFlight.clear();
    _owner = null;
  }

  static Future<Map<String, dynamic>> load(String source,
      Map<String, dynamic> room, Future<Map<String, dynamic>> Function() fetch,
      {bool force = false}) {
    final key = jsonEncode([source, room]);
    final old = _values[key];
    bool unexpired(Map<String, dynamic> data) {
      final lines = data['lines'];
      if (lines is! List || lines.isEmpty) return false;
      return lines.every((line) {
        final expiry = line is Map
            ? DateTime.tryParse('${line['expires_at'] ?? ''}')
            : null;
        return expiry == null ||
            expiry.isAfter(DateTime.now().add(const Duration(seconds: 15)));
      });
    }

    if (!force &&
        old != null &&
        unexpired(old.value) &&
        DateTime.now().difference(old.at) < const Duration(seconds: 30))
      return Future.value(old.value);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final epoch = _epoch;
    final result = Future<Map<String, dynamic>>.sync(fetch);
    _inFlight[key] = result;
    unawaited(result.then((value) {
      if (epoch == _epoch && unexpired(value)) {
        if (_values.length >= 100) _values.remove(_values.keys.first);
        _values[key] = (value: value, at: DateTime.now());
      }
    }, onError: (Object _, StackTrace __) {}).whenComplete(() {
      if (identical(_inFlight[key], result)) _inFlight.remove(key);
    }));
    return result;
  }
}
