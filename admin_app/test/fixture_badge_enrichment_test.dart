import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/fixture_badge_enrichment.dart';

void main() {
  final source = <Map<String, dynamic>>[
    {
      'home_name':'Turkey', 'away_name':'Belgium',
      'kickoff_at':'2026-11-12T17:00:00Z',
      'home_logo':null,'away_logo':null,
    }
  ];
  test('lookup all missing-badge fixture dates, not only first source row', () {
    expect(missingBadgeUtcDates([
      {'kickoff_at': '2026-11-12T17:00:00Z', 'home_logo': null, 'away_logo': null},
      {'kickoff_at': '2026-11-13T01:00:00Z', 'home_logo': null, 'away_logo': null},
      {'kickoff_at': '2026-11-13T20:00:00Z', 'home_logo': null, 'away_logo': null},
      {'kickoff_at': '2026-11-14T04:00:00Z',
       'home_logo': 'https://example.org/one.png',
       'away_logo': 'https://example.org/two.png'},
    ]), ['2026-11-12', '2026-11-13']);
  });
  test('source badges are never overwritten just because another match lacks logos', () {
    final rows = mergeVerifiedFootballBadges([
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:00:00Z',
        'home_logo': 'https://real.example.org/turkey.png',
        'away_logo': null,
      }
    ], [
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:30:00Z',
        'home_logo': 'https://new.example.org/turkey.png',
        'away_logo': 'https://new.example.org/belgium.png',
      }
    ]);
    expect(rows.single['home_logo'], 'https://real.example.org/turkey.png');
    expect(rows.single['away_logo'], 'https://new.example.org/belgium.png');
  });
  test('hotlink-blocked provider badge retains exact-match secondary URL', () {
    final rows = mergeVerifiedFootballBadges([
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:00:00Z',
        'home_logo': 'https://provider.example.org/turkey.png',
        'away_logo': 'https://provider.example.org/belgium.png',
      }
    ], [
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:20:00Z',
        'home_logo': 'https://cola.example.org/turkey.png',
        'away_logo': 'https://cola.example.org/belgium.png',
      }
    ]);
    expect(rows.single['home_logo'], 'https://provider.example.org/turkey.png');
    expect(rows.single['home_logo_fallback'], 'https://cola.example.org/turkey.png');
    expect(rows.single['away_logo_fallback'], 'https://cola.example.org/belgium.png');
  });
  test('two matched feeds contribute opposite team logos', () {
    final rows = mergeVerifiedFootballBadges(source, [
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:00:00Z',
        'home_logo': 'https://cola.example.org/turkey.png',
      },
      {
        'home_name': 'Turkey', 'away_name': 'Belgium',
        'kickoff_at': '2026-11-12T17:30:00Z',
        'away_logo': 'https://football.example.org/belgium.png',
      }
    ]);
    expect(rows.single['home_logo'], 'https://cola.example.org/turkey.png');
    expect(rows.single['away_logo'], 'https://football.example.org/belgium.png');
  });
  test('matching trusted football fixture restores both country team badges', () {
    final rows = mergeVerifiedFootballBadges(source, [
      {
        'home_name':'Türkiye','away_name':'Belgium',
        'kickoff_at':'2026-11-12T18:00:00Z',
        'home_logo':'https://logos.example.org/turkey.png',
        'away_logo':'https://logos.example.org/belgium.png'
      }
    ]);
    expect(rows.single['home_logo'],'https://logos.example.org/turkey.png');
    expect(rows.single['away_logo'],'https://logos.example.org/belgium.png');
  });
  test('incorrect team pair never supplies logos', () {
    final rows = mergeVerifiedFootballBadges(source, [
      {
        'home_name':'Germany','away_name':'Belgium',
        'kickoff_at':'2026-11-12T17:00:00Z',
        'home_logo':'https://logos.example.org/not-turkey.png'
      }
    ]);
    expect(rows.single['home_logo'],isNull);
  });
  test('stale kickoff and invalid logo URLs never substitute team badges', () {
    final rows = mergeVerifiedFootballBadges(source, [
      {
        'home_name':'Turkey','away_name':'Belgium',
        'kickoff_at':'2026-11-14T17:00:00Z',
        'home_logo':'https://logos.example.org/turkey.png',
      },
      {
        'home_name':'Turkey','away_name':'Belgium',
        'kickoff_at':'2026-11-12T17:00:00Z',
        'home_logo':'http://192.168.1.7/logo.png',
        'away_logo':'javascript:bad()',
      }
    ]);
    expect(rows.single['home_logo'],isNull);
    expect(rows.single['away_logo'],isNull);
  });
  test('existing valid provider logo remains unchanged', () {
    final preserved = [
      {...source.single,'home_logo':'https://original.example.org/logo.png'}
    ];
    final rows = mergeVerifiedFootballBadges(preserved, [
      {
        'home_name':'Turkey','away_name':'Belgium',
        'kickoff_at':'2026-11-12T17:00:00Z',
        'home_logo':'https://replacement.example.org/logo.png',
        'away_logo':'https://replacement.example.org/belgium.png'
      }
    ]);
    expect(rows.single['home_logo'],'https://original.example.org/logo.png');
    expect(rows.single['away_logo'],'https://replacement.example.org/belgium.png');
  });
}
