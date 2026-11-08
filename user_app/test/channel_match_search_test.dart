import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/channel_match_search.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  Map<String, dynamic> programme(String text, {int minutes = 0}) => {
    'title': text, 'start': now.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
    'end': now.add(Duration(minutes: minutes + 120)).millisecondsSinceEpoch,
  };
  test('Napoli team search finds a programme even when the channel has a different name', () {
    final rows = [programme('Napoli vs Inter Milan')];
    expect(channelMatchesProgrammeQuery({'name':'TNT Sports 1'}, rows, 'Napoli'), isTrue);
    expect(channelMatchesProgrammeQuery({'name':'TNT Sports 1'}, rows, 'Napoli Arsenal'), isFalse);
    expect(currentFootballProgramme(programme('Replay: Napoli vs Inter Milan'), now: now), isFalse);
    expect(currentFootballProgramme(programme('Napoli vs Inter Milan', minutes: -200), now: now), isFalse);
  });
  test('selected match needs both teams and a nearby kickoff, not a highlight or another fixture', () {
    final match = {'home_team':'SSC Napoli','away_team':'Inter Milan','kickoff_at':now.toIso8601String()};
    expect(programmeCoversMatch(programme('Napoli vs Inter Milan'), match, now: now), isTrue);
    expect(programmeCoversMatch(programme('Serie A: Napoli - Inter Milan'), match, now: now), isTrue);
    expect(programmeCoversMatch(programme('Napoli vs Inter Milan', minutes: 180), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Napoli vs Roma'), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Preview: Napoli vs Inter Milan'), match, now: now), isFalse);
    expect(programmeCoversMatch(programme('Inter Milan vs Atalanta'),
      {'home_team':'Inter Milan','away_team':'AC Milan','kickoff_at':now.toIso8601String()},now: now), isFalse);
  });
}
