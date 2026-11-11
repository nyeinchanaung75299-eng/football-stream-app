import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/big_match_source_policy.dart';

void main() {
  test('Pick Big Matches has exactly ColaTV, CricHD and Score088TV', () {
    expect(pickBigMatchProviders.keys.toList(), ['cola', 'crichd', 'score088']);
    expect(pickBigMatchProviders.values.toList(), ['ColaTV', 'CricHD', 'Score088TV']);
  });
  test('Stream-only source providers cannot be selected for Pick Big Matches', () {
    for (final source in ['soco', 'yyzb', 'fawa', 'arena', 'camel',
      'xoilac', 'livetv', 'rojadirecta', 'roxie', 'vipbox', 'viprow',
      'sports808', 'kooralive', 'livextv', 'streamfree', 'ppv']) {
      expect(isPickBigMatchProvider(source), isFalse, reason: source);
    }
    for (final source in pickBigMatchProviders.keys) {
      expect(isPickBigMatchProvider(source), isTrue);
    }
  });
}
