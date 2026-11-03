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
}
