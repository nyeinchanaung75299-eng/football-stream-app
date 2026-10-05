import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  void Function(double value)? onProgress,
}) async {
  final client = http.Client();
  final request = http.Request('GET', Uri.parse(url));
  request.headers['Accept'] = 'application/vnd.android.package-archive';
  request.headers['Cache-Control'] = 'no-cache';

  try {
    final response = await client.send(request).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'APK download failed (HTTP ${response.statusCode}).',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/NCA-update.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite();
    final total = response.contentLength ?? 0;
    var received = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        onProgress?.call(received / total);
      }
    }
    await sink.flush();
    await sink.close();
    onProgress?.call(1);

    final expected = expectedSha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      if (await file.exists()) await file.delete();
      throw const FormatException(
        'Update manifest is missing a valid SHA-256.',
      );
    }

    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != expected) {
      if (await file.exists()) await file.delete();
      throw StateError('Downloaded APK failed SHA-256 verification.');
    }

    final openResult = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (openResult.type != ResultType.done) {
      throw StateError(
        'Could not open the Android installer: ${openResult.message}',
      );
    }
  } finally {
    client.close();
  }
}
