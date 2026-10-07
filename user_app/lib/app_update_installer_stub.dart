import 'app_update_cancellation.dart';

Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  void Function(double value)? onProgress,
  ApkDownloadCancellation? cancellation,
}) async {
  throw UnsupportedError('APK install is only available on Android.');
}
