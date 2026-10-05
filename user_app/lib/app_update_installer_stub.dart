Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  void Function(double value)? onProgress,
}) async {
  throw UnsupportedError('APK install is only available on Android.');
}
