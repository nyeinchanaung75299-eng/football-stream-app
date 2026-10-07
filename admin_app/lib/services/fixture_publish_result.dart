class FixturePublishResult {
  const FixturePublishResult({
    required this.publishedIds,
    required this.skippedDeleted,
  });

  final List<String> publishedIds;
  final int skippedDeleted;

  factory FixturePublishResult.fromResponse(dynamic response) {
    if (response is! Map ||
        response['published_ids'] is! List ||
        response['skipped_deleted'] is! int) {
      throw const FormatException('Invalid match publish response.');
    }
    final ids = response['published_ids'] as List;
    if (ids.any((id) => id is! String || id.isEmpty)) {
      throw const FormatException('Invalid published match IDs.');
    }
    return FixturePublishResult(
      publishedIds: List<String>.from(ids),
      skippedDeleted: response['skipped_deleted'] as int,
    );
  }
}

Map<String, dynamic> fixturePublishInput(Map<String, dynamic> fixture) => {
      'external_fixture_id': fixture['fixture_id'],
      'source': (fixture['provider'] ?? 'api_football').toString(),
      'league': fixture['league_name'],
      'home_team': fixture['home_name'],
      'away_team': fixture['away_name'],
      'home_logo_url': fixture['home_logo'],
      'away_logo_url': fixture['away_logo'],
      'kickoff_at': fixture['kickoff_at'],
      'status_short': fixture['status_short'] ?? 'NS',
      'is_live': fixture['is_live'] == true,
    };
