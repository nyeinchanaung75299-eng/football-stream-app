import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/repository_logo.dart';

void main() {
  test(
      'legacy image routes become original URLs without changing delivery policy',
      () {
    for (final url in [
      'https://nca-network-backup-test.vercel.app/team-logos/123',
      'https://nca25-live-relay.vercel.app/api/channel-logo?team=123',
      'https://football-api.nyeinchanaung.us.ci/team-logos/123',
      'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/viewer-network-api/team-logos/123?apikey=public',
    ])
      expect(originalRepositoryLogoUrl(url),
          'https://img.sofascore.com/api/v1/team/123/image');
    expect(
        repositoryLogoUrl(originalRepositoryLogoUrl(
            'https://nca-network-backup-test.vercel.app/team-logos/123')),
        contains('/viewer-network-api/team-logos/123'));
  });
  test('custom badges and lookalike/private image routes are preserved', () {
    for (final url in [
      'https://operator.example/crest.png',
      'https://nca25-live-relay.vercel.app.attacker.example/team-logos/123',
      'https://someone@nca25-live-relay.vercel.app/team-logos/123',
      'https://nca25-live-relay.vercel.app:444/team-logos/123',
      'https://nca25-live-relay.vercel.app/team-logos/invalid',
    ]) expect(originalRepositoryLogoUrl(url), url);
  });
}
