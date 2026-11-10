import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/app_update_service.dart';

void main() {
  test('GitHub Pages APK downloads stay on the reachable GitHub host', () {
    expect(
      vpnFreeUpdateUrl(
        'https://nyeinchanaung75299-eng.github.io/'
        'football-stream-app/releases/NCA-arm64-v8a-latest.apk?build=30695',
      ),
      'https://nyeinchanaung75299-eng.github.io/'
      'football-stream-app/releases/NCA-arm64-v8a-latest.apk?build=30695',
    );
  });

  test('Cloudflare release URLs fall back to the reachable GitHub host', () {
    expect(
      vpnFreeUpdateUrl(
        'https://nca.nyeinchanaung.us.ci/'
        'football-stream-app/releases/NCA-arm64-v8a-latest.apk',
      ),
      'https://nyeinchanaung75299-eng.github.io/'
      'football-stream-app/releases/NCA-arm64-v8a-latest.apk',
    );
  });

  test('non-viewer update URLs remain unchanged', () {
    const url = 'https://downloads.example.com/NCA-latest.apk';
    expect(vpnFreeUpdateUrl(url), url);
  });

  const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const canonicalApk =
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/releases/NCA-arm64-v8a-latest.apk';

  test('Viewer update first checks canonical signed-release feed', () {
    expect(AppUpdateService.manifestUrls.first,
      'https://raw.githubusercontent.com/nyeinchanaung75299-eng/'
      'football-stream-app/feed/public/releases/latest.json');
  });

  test('Only the expected ARM64 Viewer APK and verified metadata are accepted', () {
    final manifest = <String, dynamic>{
      'version_name': '9.8.0',
      'build_number': 30746,
      'abi': 'arm64-v8a',
      'apk_url': canonicalApk,
      'sha256': digest,
      'size_bytes': 21350466,
    };
    expect(validViewerRelease(manifest), isTrue);
    for (final changes in <Map<String, dynamic>>[
      {'app': 'nca_admin'},
      {'abi': 'universal'},
      {'apk_url': canonicalApk.replaceFirst('raw.githubusercontent.com',
          'untrusted.example')},
      {'apk_url': canonicalApk.replaceFirst('NCA-arm64', 'NCA-admin-arm64')},
      {'apk_url': '$canonicalApk?download=1'},
      {'sha256': 'invalid'},
      {'build_number': 0},
      {'size_bytes': 0},
      {'size_bytes': 51 * 1024 * 1024},
      {'version_name': 'latest'},
    ]) {
      expect(validViewerRelease({...manifest, ...changes}), isFalse,
        reason: changes.toString());
    }
  });
}
