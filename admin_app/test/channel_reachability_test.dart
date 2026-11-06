import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/channel_reachability.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 9);
  Map<String, dynamic> line({
    bool active = true,
    String status = 'healthy',
    String? checked = '2026-11-02T08:55:00Z',
  }) => {
    'is_active': active,
    'health_status': status,
    'last_checked_at': checked,
    'health_latency_ms': 120,
  };

  test('recent first-byte check is reachable, not playback verified', () {
    final result = assessChannelReachability([line()], now: now);
    expect(result.status, 'reachable');
    expect(result.activeLines, 1);
    expect(result.maxLatencyMs, 120);
  });

  test('old success is stale, never displayed as current reachable', () {
    final result = assessChannelReachability([
      line(checked: '2026-11-01T20:00:00Z'),
    ], now: now);
    expect(result.status, 'stale');
  });

  test('missing check remains stale even when status says healthy', () {
    expect(
      assessChannelReachability([line(checked: null)], now: now).status,
      'stale',
    );
  });

  test('multiple lines with one old check are stale', () {
    expect(assessChannelReachability([
      line(),
      line(checked: '2026-11-01T18:00:00Z'),
    ], now: now).status, 'stale');
  });

  test('current network failure is failed, slow is slow', () {
    expect(assessChannelReachability([line(status: 'failed')], now: now).status,
        'failed');
    expect(assessChannelReachability([line(status: 'slow')], now: now).status,
        'slow');
  });

  test('a working backup and failed primary are partial, not wholly failed', () {
    final result = assessChannelReachability([line(), line(status: 'failed')], now: now);
    expect(result.status, 'partial');
    expect(result.reachableLines, 1);
    expect(result.failedLines, 1);
    expect(result.activeLines, 2);
  });

  test('ignores inactive lines and avoids future timestamps', () {
    expect(assessChannelReachability([
      line(active: false),
    ], now: now).status, 'unknown');
    expect(assessChannelReachability([
      line(checked: '2026-11-03T08:00:00Z'),
    ], now: now).status, 'stale');
  });
}
