import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  Map<String, dynamic> row(String source, String home) => {
    'source': source,
    'source_id': home.toLowerCase().replaceAll(' ', '-'),
    'home_team': home,
    'away_team': 'Away',
    'anchors': const [],
  };

  test('status cache is reused for two minutes and expires safely', () {
    final now = DateTime.utc(2026, 11, 1, 12);
    expect(sourceStatusIsFresh(null, now), isFalse);
    expect(sourceStatusIsFresh(now.subtract(const Duration(seconds: 30)), now),
        isTrue);
    expect(sourceStatusIsFresh(now.subtract(const Duration(minutes: 2)), now),
        isFalse);
    expect(sourceStatusIsFresh(now.add(const Duration(seconds: 1)), now),
        isFalse);
  });

  test('accepts only rows proven to belong to the selected provider', () {
    final rows = validateSourceMatchRows({
      'source': 'cola',
      'matches': [row('cola', 'ColaTV fixture')],
    }, 'cola');

    expect(rows, hasLength(1));
    expect(rows.single['home_team'], 'ColaTV fixture');
  });

  test('rejects a Soco payload shown under ColaTV', () {
    expect(
      () => validateSourceMatchRows({
        'source': 'soco',
        'matches': [row('soco', 'Deportivo Pasto')],
      }, 'cola'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a mixed-provider row even when the envelope is correct', () {
    expect(
      () => validateSourceMatchRows({
        'source': 'cola',
        'matches': [row('soco', 'Wrong fixture')],
      }, 'cola'),
      throwsA(isA<FormatException>()),
    );
  });
}
