import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/soco_import_page.dart';

void main() {
  test('Native Admin source page rejects logout and account switching', () {
    bool active(String? user) => sourceSessionMatches(
      pageUser: 'admin-a',
      activeUser: user,
      pageGeneration: 0,
      currentGeneration: 0,
      isWeb: false,
    );
    expect(active('admin-a'), isTrue);
    expect(active(null), isFalse);
    expect(active('admin-b'), isFalse);
  });

  test('Web same-account relogin cannot reuse prior-session source page', () {
    expect(sourceSessionMatches(
      pageUser: 'admin-a',
      activeUser: 'admin-a',
      pageGeneration: 3,
      currentGeneration: 4,
      isWeb: true,
    ), isFalse);
  });

  test('Native identity check is independent of Web-only cache generations', () {
    expect(sourceSessionMatches(
      pageUser: 'admin-a',
      activeUser: 'admin-a',
      pageGeneration: 3,
      currentGeneration: 4,
      isWeb: false,
    ), isTrue);
  });
}
