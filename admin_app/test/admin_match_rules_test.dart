import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/admin_match_rules.dart';

void main() {
  final now = DateTime.utc(2026, 10, 6, 12);
  final currentMatch = <String, dynamic>{
    'is_active': true,
    'is_featured': true,
    'publish_state': 'published',
    'is_live': false,
    'kickoff_at': now.add(const Duration(hours: 1)).toIso8601String(),
  };

  test('All includes inactive, draft, unfeatured, and past matches', () {
    for (final change in [
      {'is_active': false},
      {'publish_state': 'draft'},
      {'is_featured': false},
      {'kickoff_at': now.subtract(const Duration(days: 1)).toIso8601String()},
    ]) {
      expect(
        isVisibleAdminMatch({...currentMatch, ...change}, view: 'all', now: now),
        isTrue,
        reason: change.toString(),
      );
      expect(
        isVisibleAdminMatch(
          {...currentMatch, ...change},
          view: 'upcoming',
          now: now,
        ),
        isFalse,
      );
    }
  });

  test('All still hides deleted rows', () {
    expect(
      isVisibleAdminMatch(
        {...currentMatch, 'deleted_at': now.toIso8601String()},
        view: 'all',
        now: now,
      ),
      isFalse,
    );
  });

  test('Live requires live and published while Upcoming accepts live past kickoff', () {
    expect(isVisibleAdminMatch(currentMatch, view: 'live', now: now), isFalse);
    final live = {
      ...currentMatch,
      'is_live': true,
      'kickoff_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
    };
    expect(isVisibleAdminMatch(live, view: 'live', now: now), isTrue);
    expect(isVisibleAdminMatch(live, view: 'upcoming', now: now), isTrue);
    expect(
      isVisibleAdminMatch({...live, 'publish_state': 'draft'}, view: 'live', now: now),
      isFalse,
    );
  });

  test('Active native and WebView lines require their selected URL', () {
    expect(
      activeStreamUrlError(
        isActive: true,
        useWebView: false,
        streamUrl: '  ',
        webViewUrl: 'https://example.com/watch',
      ),
      'Paste a stream URL.',
    );
    expect(
      activeStreamUrlError(
        isActive: true,
        useWebView: true,
        streamUrl: 'https://example.com/live.m3u8',
        webViewUrl: '',
      ),
      'Paste a WebView URL.',
    );
    expect(
      activeStreamUrlError(
        isActive: false,
        useWebView: false,
        streamUrl: '',
        webViewUrl: '',
      ),
      isNull,
    );
  });

  test('URL validation accepts signed HTTP URLs and rejects unusable values', () {
    for (final value in ['https://example.com/live.mpd?token=a%2Fb', ' http://example.com/watch ']) {
      expect(
        activeStreamUrlError(
          isActive: true,
          useWebView: false,
          streamUrl: value,
          webViewUrl: '',
        ),
        isNull,
      );
    }
    for (final value in ['example.com/live', '/live.m3u8', 'https://', 'https://example.com/a b']) {
      expect(
        activeStreamUrlError(
          isActive: true,
          useWebView: true,
          streamUrl: '',
          webViewUrl: value,
        ),
        isNotNull,
      );
    }
  });
}
