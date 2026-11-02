/// Existing server-side health probes read only the first stream bytes.
/// Reachability must not be mistaken for successful media playback.
const streamProbeFreshness = Duration(hours: 2);

class ChannelReachability {
  const ChannelReachability({
    required this.status,
    required this.activeLines,
    required this.checkedAt,
    required this.maxLatencyMs,
  });

  /// reachable, stale, slow, failed or unknown. NOT a playback status.
  final String status;
  final int activeLines;
  final DateTime? checkedAt;
  final int? maxLatencyMs;
}

ChannelReachability assessChannelReachability(
  Iterable<Map<String, dynamic>> lines, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toUtc();
  final active = lines.where((line) => line['is_active'] == true).toList();
  if (active.isEmpty) {
    return const ChannelReachability(
      status: 'unknown', activeLines: 0,
      checkedAt: null, maxLatencyMs: null,
    );
  }

  final validChecks = <DateTime>[];
  var missingOrExpired = false;
  final latencies = <int>[];
  final statuses = <String>[];

  for (final line in active) {
    statuses.add((line['health_status'] ?? 'unknown').toString());
    final raw = DateTime.tryParse(line['last_checked_at']?.toString() ?? '');
    if (raw == null ||
        raw.isAfter(current.add(const Duration(minutes: 1))) ||
        current.difference(raw.toUtc()) > streamProbeFreshness) {
      missingOrExpired = true;
    } else {
      validChecks.add(raw.toUtc());
    }
    final value = line['health_latency_ms'];
    if (value is num && value > 0) latencies.add(value.toInt());
  }

  // Never promote an old first-byte response to a current playback guarantee.
  final status = missingOrExpired
      ? 'stale'
      : statuses.contains('failed')
          ? 'failed'
          : statuses.contains('slow')
              ? 'slow'
              : statuses.every((value) => value == 'healthy')
                  ? 'reachable'
                  : 'unknown';

  return ChannelReachability(
    status: status,
    activeLines: active.length,
    checkedAt: validChecks.isEmpty ? null
        : (validChecks..sort((a, b) => b.compareTo(a))).first,
    maxLatencyMs: latencies.isEmpty ? null
        : latencies.reduce((a, b) => a > b ? a : b),
  );
}
