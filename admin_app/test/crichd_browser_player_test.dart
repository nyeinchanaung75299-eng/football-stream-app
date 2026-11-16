import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  test('CricHD browser fallback accepts a publisher-linked HTTPS player', () {
    final page = cricHdBrowserPlayerPage(
      'https://playerbee.top/charlie/germany-vs-netherlands/3707',
    );
    expect(page, isNotNull);
    expect(page!.host, 'playerbee.top');
  });

  test('CricHD browser fallback never opens arbitrary or unsafe URLs', () {
    for (final value in <String?>[
      null,
      '',
      'http://playerbee.top/charlie/example',
      'https://playerbee.top:8443/charlie/example',
      'https://user:password@playerbee.top/charlie/example',
      'https://playerbee.top.evil.example/charlie/example',
      'https://other.example/charlie/example',
      'javascript:alert(1)',
      'https://playerbee.top/',
    ]) {
      expect(cricHdBrowserPlayerPage(value), isNull, reason: '$value');
    }
  });
}
