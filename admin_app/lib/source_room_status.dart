/// Resolve the badge following an explicit Admin source tap.
///
/// A third-party public player denying a server-side request (HTTP 401/403),
/// or returning no directly published HLS URL, is not proof of an offline
/// stream. Keep these unverified sources UNKNOWN unless a health probe
/// positively confirmed playback readiness. Existing primary providers
/// retain their original room status semantics.
String sourceRoomStatusFromLines({
  required String provider,
  required bool isLive,
  required bool hasHealthy,
  required int lineCount,
}) {
  if (isLive) return 'live';
  if (const {'crichd', 'roxie'}.contains(provider)) {
    return hasHealthy ? 'ready' : 'unknown';
  }
  return hasHealthy || lineCount > 0 ? 'ready' : 'offline';
}
