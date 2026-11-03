import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app_update_service.dart';

void main() {
  test('GitHub Pages APK downloads use the VPN-free viewer mirror', () {
    expect(
      vpnFreeUpdateUrl(
        'https://nyeinchanaung75299-eng.github.io/'
        'football-stream-app/releases/NCA-latest.apk?build=12689',
      ),
      'https://nca.nyeinchanaung.us.ci/'
      'football-stream-app/releases/NCA-latest.apk?build=12689',
    );
  });

  test('non-viewer update URLs remain unchanged', () {
    const url = 'https://downloads.example.com/NCA-latest.apk';
    expect(vpnFreeUpdateUrl(url), url);
  });
}
