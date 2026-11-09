import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/admin_update_service.dart';

void main() {
  test('Admin update manifest uses the published feed directly, not 404 Pages', () {
    expect(AdminUpdateService.manifestUrls, hasLength(1));
    expect(AdminUpdateService.manifestUrls.single,
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/releases/admin-latest.json');
  });

  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const apk = 'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/releases/NCA-admin-arm64-v8a-latest.apk';

  test('Admin updater validates app identity, exact host, ABI and SHA-256', () {
    final good = <String, dynamic>{
      'app': 'nca_admin',
      'abi': 'arm64-v8a',
      'apk_url': apk,
      'sha256': sha,
      'build_number': 30001,
    };
    expect(AdminUpdateService.validAdminRelease(good), isTrue);
    for (final edit in <Map<String, dynamic>>[
      {'app': 'nca_viewer'},
      {'abi': 'armeabi-v7a'},
      {'apk_url': apk.replaceFirst('raw.githubusercontent.com', 'example.com')},
      {'apk_url': apk.replaceFirst('NCA-admin-', 'NCA-')},
      {'apk_url': '$apk?download=1'},
      {'sha256': 'not-a-checksum'},
    ]) {
      expect(AdminUpdateService.validAdminRelease({...good, ...edit}), isFalse);
    }
  });
}
