import 'apk_action.dart';
import 'dart:ui' show Rect;

Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  ApkAction action = ApkAction.install,
  Rect? sharePositionOrigin,
  void Function(double value)? onProgress,
}) async {
  throw UnsupportedError('APK install is only available on Android.');
}
