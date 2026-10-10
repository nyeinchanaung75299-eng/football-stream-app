import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/football_english.dart';
import 'package:football_viewer/source_match_discovery.dart';

void main() {
  test('screenshot clubs and common leagues have verified English labels', () {
    expect(englishKnownFootballName('帕德博恩'), 'SC Paderborn 07');
    expect(englishKnownFootballName('斯图加特'), 'VfB Stuttgart');
    expect(englishKnownFootballName('柏林联合'), '1. FC Union Berlin');
    expect(englishKnownFootballName('埃弗斯堡'), 'SV 07 Elversberg');
    expect(
      englishKnownFootballName('英超', kind: 'league'),
      'English Premier League',
    );
    expect(englishKnownFootballName('德甲', kind: 'league'), 'Bundesliga');
    expect(
      englishKnownFootballName('德青联', kind: 'league'),
      'German Youth League',
    );
    expect(englishKnownFootballName('帕德博恩U19'), 'SC Paderborn 07 U19');
  });

  test(
    'real English fields beat raw aliases and blank or invalid English fields',
    () {
      final row = englishSourceMatch({
        'source_id': 'fixture-42',
        'home_team_en': 'Paderborn English feed name',
        'home_team': '帕德博恩',
        'away_team_en': '  ',
        'away_team': {'name_en': 'VfB Stuttgart', 'name': '斯图加特'},
        'league_en': '德甲',
        'league': 'German provider fallback',
      }, 'yyzb');
      expect(row['home_team'], 'Paderborn English feed name');
      expect(row['away_team'], 'VfB Stuttgart');
      expect(row['league'], 'Bundesliga');
    },
  );

  test(
    'unknown YYZB names use stable references without changing source identity',
    () {
      final original = <String, dynamic>{
        'source_id': 'fixture-42',
        'schedule_id': 42,
        'home_team': '未知球队',
        'away_team': 'ทีมทดสอบ',
        'league': 'မသိလိဂ်',
        'league_id': 'league-9',
        'match_time': '2026-10-10T12:30:00Z',
        'hot': true,
        'anchors': [
          {'room_num': 'room-7', 'nick_name': '老白聊球'},
          {'room_num': 'room-8', 'nick_name': '斯姐開波(粵語)'},
        ],
      };
      final translated = englishSourceMatch(original, 'yyzb');
      expect(translated['home_team'], 'Home team (fixture-42)');
      expect(translated['away_team'], 'Away team (fixture-42)');
      expect(translated['league'], 'Football league (league-9)');
      expect(translated['original_home_team'], '未知球队');
      expect(translated['source_id'], original['source_id']);
      expect(translated['schedule_id'], original['schedule_id']);
      expect(translated['match_time'], original['match_time']);
      expect(translated['hot'], true);
      expect(sourceMatchAnchors(translated, 'yyzb')[0]['room_num'], 'room-7');
      expect(
        sourceMatchAnchors(translated, 'yyzb')[0]['nick_name'],
        'Streamer 1',
      );
      expect(
        sourceMatchAnchors(translated, 'yyzb')[1]['nick_name'],
        'Streamer 2 (Cantonese)',
      );
      expect((original['anchors'] as List)[0]['nick_name'], '老白聊球');
      expect(original['home_team'], '未知球队');
      expect(englishSourceMatch(translated, 'yyzb'), translated);
    },
  );

  test('English search finds canonical names from legacy mirror rows', () {
    final translated = englishSourceMatch({
      'source_id': 'mirror-42',
      'home_team': '帕德博恩',
      'away_team': '斯图加特',
      'league': '德甲',
    }, 'yyzb');
    expect(
      filterSourceMatches(
        [translated],
        todayOnly: false,
        query: 'paderborn bundesliga',
      ),
      [translated],
    );
  });

  test('manual names and other sources keep unknown Unicode text intact', () {
    final row = <String, dynamic>{'home_team': '未知球队足球', 'league': 'မသိလိဂ်'};
    expect(englishKnownFootballName('未知球队足球'), '未知球队足球');
    expect(englishKnownFootballName('FC Köln'), 'FC Köln');
    expect(englishSourceMatch(row, 'soco'), same(row));
    expect(englishSourceMatch(row, 'live'), same(row));
  });

  test(
    'known audio language survives English streamer and legacy line labels',
    () {
      expect(
        englishSourceAnchorName({'nick_name': '达达（粤语）'}, 2),
        'Streamer 3 (Cantonese)',
      );
      expect(
        englishSourceAnchorName({'nick_name': '球哥(普通话)'}, 0),
        'Streamer 1 (Mandarin)',
      );
      expect(englishSourceAnchorName({'nick_name': '曼联'}, 0), 'Streamer 1');
      expect(
        englishSourceAnchorName({
          'nick_name_en': 'Match Radio',
          'original_nick_name': '球哥(国语)',
        }, 0),
        'Match Radio (Mandarin)',
      );
      expect(
        englishStreamLabel('YYZB • 老白聊球 • HD (1080p) • HLS', index: 1),
        'YYZB • Streamer 2 • HD (1080p) • HLS',
      );
      expect(
        englishStreamLabel('钰儿 (粤语) • SD (720p) • FLV', index: 3),
        'Streamer 4 (Cantonese) • SD (720p) • FLV',
      );
      expect(
        englishStreamLabel('中文 1080p HLS', index: 0),
        'Streamer 1 • 1080p HLS',
      );
      expect(
        englishStreamLabel('Radio One • 1080p • DASH'),
        'Radio One • 1080p • DASH',
      );
    },
  );
}
