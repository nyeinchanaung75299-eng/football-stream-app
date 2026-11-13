import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/match_line_label.dart';

void main() {
  test('removes match prefix but retains source and quality', () {
    expect(conciseMatchLineLabel('Serbia vs Germany • FUBO SPORTS - AQ'),
        'FUBO SPORTS - AQ');
    expect(conciseMatchLineLabel('Serbia vs Germany • BEIN ARABIC HD'),
        'BEIN ARABIC HD');
    expect(conciseMatchLineLabel('Arsenal v Chelsea · Server 2 (HLS)'),
        'Server 2 (HLS)');
  });
  test('leaves normal and malformed labels unchanged', () {
    expect(conciseMatchLineLabel('FUBO SPORTS - AQ'), 'FUBO SPORTS - AQ');
    expect(conciseMatchLineLabel('BEIN ARABIC HD • 1080p'), 'BEIN ARABIC HD • 1080p');
    expect(conciseMatchLineLabel('Serbia vs Germany • '), 'Serbia vs Germany •');
  });
}
