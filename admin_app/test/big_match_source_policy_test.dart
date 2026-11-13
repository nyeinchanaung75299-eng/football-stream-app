import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/big_match_source_policy.dart';

void main() {
  test('Pick Big Matches has only ColaTV and Repository Match', () {
    expect(pickBigMatchProviders.keys.toList(), ['cola', 'repository']);
    expect(pickBigMatchProviders.values.toList(), ['ColaTV', 'Repository Match']);
  });
  test('Stream-only source providers cannot be selected for Pick Big Matches', () {
    for (final source in ['soco', 'yyzb', 'fawa', 'arena', 'camel',
      'xoilac', 'livetv', 'rojadirecta', 'roxie', 'vipbox', 'viprow',
      'sports808', 'kooralive', 'livextv', 'streamfree', 'ppv', 'crichd', 'score088']) {
      expect(isPickBigMatchProvider(source), isFalse, reason: source);
    }
    for (final source in pickBigMatchProviders.keys) {
      expect(isPickBigMatchProvider(source), isTrue);
    }
  });
}
