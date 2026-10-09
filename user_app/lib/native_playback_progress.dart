/// Watches native media progress using monotonic time, excluding deliberate
/// pauses and time spent in the background. An unpaused player alone does not
/// prove that media has started.
class NativePlaybackProgress {
  NativePlaybackProgress({
    this.startupTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 25),
  });

  final Duration startupTimeout;
  final Duration stallTimeout;
  Duration _excluded = Duration.zero;
  Duration? _suspendedAt;
  Duration _lastPosition = Duration.zero;
  Duration _lastProgressAt = Duration.zero;
  Duration? startupElapsed;

  bool get started => startupElapsed != null;
  bool get suspended => _suspendedAt != null;

  Duration activeElapsed(Duration now) {
    final elapsed =
        now -
        _excluded -
        (_suspendedAt == null ? Duration.zero : now - _suspendedAt!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  void setSuspended(bool value, Duration now) {
    if (value == suspended) return;
    if (value) {
      _suspendedAt = now;
    } else {
      _excluded += now - _suspendedAt!;
      _suspendedAt = null;
    }
  }

  /// Returns true only when the media clock advances. A reset/seek backwards
  /// establishes a new baseline rather than falsely completing startup.
  bool observePosition(Duration position, Duration now) {
    if (suspended) return false;
    if (position < _lastPosition) {
      _lastPosition = position;
      return false;
    }
    if (position - _lastPosition < const Duration(milliseconds: 200)) {
      return false;
    }
    _lastPosition = position;
    _lastProgressAt = activeElapsed(now);
    startupElapsed ??= _lastProgressAt;
    return true;
  }

  String? timeoutReason(Duration now) {
    if (suspended) return null;
    final elapsed = activeElapsed(now);
    if (!started && elapsed >= startupTimeout) return 'startup_timeout';
    if (started && elapsed - _lastProgressAt >= stallTimeout) {
      return 'stall_timeout';
    }
    return null;
  }
}
