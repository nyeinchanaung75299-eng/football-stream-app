import 'dart:async';
import 'hls_candidate_verifier.dart';
import 'stream_detector_service.dart';

/// One visible detector document. Navigation invalidates pending validation
/// and selection timers, so an older page cannot populate a new page's picker.
class HlsDetectionSession {
  HlsDetectionSession(
      {required this.quickSelect,
      required this.onChanged,
      required this.onSelected,
      Future<HlsCandidateCheck> Function(DetectedStream)? verify,
      HlsCandidateVerifier? verifier,
      this.quietPeriod = const Duration(seconds: 3)})
      : _verifier = verifier ?? HlsCandidateVerifier() {
    _verify = verify ?? _verifier.verify;
  }
  final bool quickSelect;
  final void Function() onChanged;
  final void Function(DetectedStream) onSelected;
  final Duration quietPeriod;
  final HlsCandidateVerifier _verifier;
  late final Future<HlsCandidateCheck> Function(DetectedStream) _verify;
  final _streams = <DetectedStream>[];
  final checks = <String, HlsCandidateCheck>{};
  final _pending = <String>{};
  final _revisions = <String, int>{};
  final _attempts = <String, int>{};
  final _mediaUrls = <String>{};
  Timer? _timer;
  int generation = 0;
  bool loaded = false, _selected = false, _disposed = false;
  List<DetectedStream> get streams => List.unmodifiable(_streams);
  bool current(int value) => !_disposed && generation == value;

  void reset({bool documentLoaded = false}) {
    generation++;
    _timer?.cancel();
    _verifier.cancel();
    _streams.clear();
    _mediaUrls.clear();
    checks.clear();
    _pending.clear();
    _revisions.clear();
    _attempts.clear();
    loaded = documentLoaded;
    _selected = false;
    if (!_disposed) onChanged();
  }

  void observe(DetectedStream stream, {Map<String, String>? headers}) {
    if (_disposed) return;
    final existing = _streams.indexWhere((v) => v.url == stream.url);
    if (existing >= 0) {
      if (headers != null) {
        final before = _streams[existing];
        final updated = before.withPublicRequestHeaders(headers);
        if (updated.referer != before.referer ||
            updated.origin != before.origin) {
          _streams[existing] = updated;
          _revisions[stream.url] = (_revisions[stream.url] ?? 0) + 1;
          checks.remove(stream.url);
          _timer?.cancel();
          onChanged();
          if (!_pending.contains(stream.url)) _check(updated);
        }
      }
      return;
    }
    if (_streams.length >= 100) return;
    _streams.insert(0, stream);
    _timer?.cancel();
    onChanged();
    _check(stream);
    _schedule();
  }

  void _check(DetectedStream stream) {
    if (!quickSelect ||
        stream.type != 'hls' ||
        (_attempts[stream.url] ?? 0) >= 3 ||
        (!_attempts.containsKey(stream.url) && _attempts.length >= 8)) return;
    final epoch = generation;
    final revision = _revisions[stream.url] ?? 0;
    _attempts[stream.url] = (_attempts[stream.url] ?? 0) + 1;
    _pending.add(stream.url);
    unawaited(Future<HlsCandidateCheck>.sync(() => _verify(stream))
        .catchError((Object _) =>
            const HlsCandidateCheck(false, 'Playlist could not be verified'))
        .then((result) {
      if (!current(epoch)) return;
      _pending.remove(stream.url);
      if (revision != (_revisions[stream.url] ?? 0)) {
        _check(_streams.firstWhere((item) => item.url == stream.url));
        return;
      }
      checks[stream.url] = result;
      onChanged();
      _schedule();
    }));
  }

  void associateMedia(Iterable<String> urls, int epoch) {
    if (!current(epoch)) return;
    var changed = false;
    for (final url in urls) {
      if (_mediaUrls.add(url)) changed = true;
    }
    // Periodic current-document rescans must not keep pushing back the
    // quiet timer when they only repeat an already associated video URL.
    if (changed) _schedule();
  }

  void documentFinished(int epoch) {
    if (!current(epoch)) return;
    loaded = true;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        !quickSelect ||
        _selected ||
        !loaded ||
        _pending.isNotEmpty) return;
    final epoch = generation;
    _timer = Timer(quietPeriod, () {
      if (!current(epoch) || _selected || !loaded || _pending.isNotEmpty)
        return;
      final only = singleObservedHlsCandidate(_streams);
      if (only == null ||
          checks[only.url]?.live != true ||
          !_mediaUrls.contains(only.url)) return;
      _selected = true;
      onSelected(only);
    });
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
