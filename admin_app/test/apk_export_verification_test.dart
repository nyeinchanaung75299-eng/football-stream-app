import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_admin/app_update_installer_io.dart';
import 'package:football_admin/apk_action.dart';

void main() {
  for (final action in ApkAction.values) {
    test('$action receives only hash-verified APK bytes', () async {
      final dir = await Directory.systemTemp.createTemp('verified-apk-test');
      final bytes = [80, 75, 3, 4, 1, 2, 3];
      var delivered = 0;
      try {
        await downloadAndInstallApk('https://release.example/app.apk',
            expectedSha256: sha256.convert(bytes).toString(),
            action: action,
            temporaryDirectory: () async => dir,
            clientFactory: () =>
                MockClient((_) async => http.Response.bytes(bytes, 200)),
            deliverVerifiedFile: (path, actual) async {
              delivered++;
              expect(actual, action);
              expect(await File(path).readAsBytes(), bytes);
            });
        expect(delivered, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    });
    test('$action cannot export or install after hash mismatch', () async {
      final dir = await Directory.systemTemp.createTemp('invalid-apk-test');
      var delivered = 0;
      try {
        await expectLater(
            downloadAndInstallApk('https://release.example/app.apk',
                expectedSha256: '0' * 64,
                action: action,
                temporaryDirectory: () async => dir,
                clientFactory: () => MockClient(
                    (_) async => http.Response.bytes([1, 2, 3], 200)),
                deliverVerifiedFile: (_, __) async {
                  delivered++;
                }),
            throwsStateError);
        expect(delivered, 0);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
}
