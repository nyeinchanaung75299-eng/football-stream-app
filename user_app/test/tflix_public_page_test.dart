import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/tflix_public_page.dart';

void main() {
  test('current public channel ID opens its original page', () {
    expect(
      tflixPublicChannelPage('channel:bein-sports-1-tr-63cb04c5'),
      'https://tflix.su/channel/bein-sports-1-tr-63cb04c5',
    );
  });

  test('external destinations and malformed catalog IDs cannot be opened', () {
    for (final id in [
      'match:bein-sports-1-tr',
      'channel:https://evil.example/',
      'channel:abc?token=x',
      'channel:abc/../../x',
      'channel:abc%2Fother',
      'channel:',
    ]) {
      expect(tflixPublicChannelPage(id), isNull);
    }
  });
}
