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

  test('accepts only rows proven to belong to the selected provider', () {
    final rows = validateSourceMatchRows({
      'source': 'streame',
      'matches': [row('streame', 'StreamCenter fixture')],
    }, 'streame');

    expect(rows, hasLength(1));
    expect(rows.single['home_team'], 'StreamCenter fixture');
  });

  test('rejects a Soco payload shown under StreamCenter', () {
    expect(
      () => validateSourceMatchRows({
        'source': 'soco',
        'matches': [row('soco', 'Deportivo Pasto')],
      }, 'streame'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a mixed-provider row even when the envelope is correct', () {
    expect(
      () => validateSourceMatchRows({
        'source': 'streame',
        'matches': [row('soco', 'Wrong fixture')],
      }, 'streame'),
      throwsA(isA<FormatException>()),
    );
  });
}
