import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/fixture_publish_result.dart';

void main() {
  test('Publish result counts persisted rows, including all-tombstoned selection', () {
    final mixed = FixturePublishResult.fromResponse({
      'published_ids': ['persisted-match-id'],
      'skipped_deleted': 2,
    });
    expect(mixed.publishedIds, ['persisted-match-id']);
    expect(mixed.publishedIds.length, 1);
    expect(mixed.skippedDeleted, 2);

    final skipped = FixturePublishResult.fromResponse({
      'published_ids': <String>[],
      'skipped_deleted': 3,
    });
    expect(skipped.publishedIds, isEmpty);
    expect(skipped.skippedDeleted, 3);
  });

  test('Invalid RPC responses cannot be reported as successful publication', () {
    for (final response in [null, {}, {'published_ids': [null], 'skipped_deleted': 0}]) {
      expect(() => FixturePublishResult.fromResponse(response), throwsFormatException);
    }
  });

  test('Fixture RPC input maps source fields without overriding publication state', () {
    expect(
      fixturePublishInput({
        'fixture_id': 123,
        'provider': 'cola',
        'league_name': 'League',
        'home_name': 'Home',
        'away_name': 'Away',
        'home_logo': 'https://example.com/home.png',
        'kickoff_at': '2026-10-06T12:00:00Z',
        'is_live': true,
      }),
      {
        'external_fixture_id': 123,
        'source': 'cola',
        'league': 'League',
        'home_team': 'Home',
        'away_team': 'Away',
        'home_logo_url': 'https://example.com/home.png',
        'away_logo_url': null,
        'kickoff_at': '2026-10-06T12:00:00Z',
        'status_short': 'NS',
        'is_live': true,
      },
    );
  });
}
