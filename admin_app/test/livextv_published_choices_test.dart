import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/livextv_published_choices.dart';

void main() {
  const page = 'https://livextv.pro/watch/32372';

  test('only actual published HD and SD selector URLs are presented', () {
    final rows = liveXtvPublishedQualityOptions([
      {
        'room_num': 'room-hd',
        'watch_url': '$page?s=1',
        'nick_name': 'HD | beIN SPORTS 5',
      },
      {
        'room_num': 'room-sd',
        'watch_url': '$page?s=2',
        'nick_name': 'SD | beIN SPORTS 5',
      },
    ], page);
    expect(rows.map((x) => x['nick_name']).toList(), [
      'HD | beIN SPORTS 5',
      'SD | beIN SPORTS 5',
    ]);
    expect(rows.map((x) => x['watch_url']).toList(), [
      '$page?s=1',
      '$page?s=2',
    ]);
    expect(rows.every((x) => x['stream_url'] == null), isTrue);
  });

  test('rejects synthetic, foreign, private, and credential selectors', () {
    final rows = liveXtvPublishedQualityOptions([
      {'room_num': 'ok', 'nick_name': 'HD', 'watch_url': '$page?s=1'},
      {'room_num': 'dup', 'nick_name': 'HD duplicate', 'watch_url': '$page?s=1'},
      {'room_num': 'bad', 'nick_name': 'SD', 'watch_url': '$page?s=3&token=abc'},
      {'room_num': 'bad', 'nick_name': 'SD', 'watch_url': 'https://evil.test/watch/32372?s=2'},
      {'room_num': 'bad', 'nick_name': 'SD', 'watch_url': 'http://livextv.pro/watch/32372?s=2'},
      {'room_num': 'bad', 'nick_name': 'SD', 'watch_url': '$page?s=1&s=2'},
      {'room_num': 'bad', 'nick_name': 'SD', 'watch_url': 'https://livextv.pro/watch/999?s=2'},
      {'room_num': '', 'nick_name': 'SD', 'watch_url': '$page?s=2'},
      {'room_num': 'room', 'nick_name': '', 'watch_url': '$page?s=2'},
    ], page);
    expect(rows.length, 1);
    expect(rows.single['room_num'], 'ok');
  });

  test('empty/unavailable HTML choices never fabricate HD/SD', () {
    expect(liveXtvPublishedQualityOptions(null, page), isEmpty);
    expect(liveXtvPublishedQualityOptions([], page), isEmpty);
    expect(
      liveXtvPublishedQualityOptions([
        {'room_num': 'one', 'nick_name': 'HD', 'watch_url': '$page?s=1'},
      ], 'https://example.test/watch/32372'),
      isEmpty,
    );
  });
}
