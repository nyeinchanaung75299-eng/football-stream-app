import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Resume incomplete downloads with a verified HTTP range. If a server ignores
/// Range and returns 200, restart the file rather than mixing APK versions.
/// The SHA-256 release manifest remains the final install gate.
Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  void Function(double value)? onProgress,
}) async {
  final expected = expectedSha256.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
    throw const FormatException('Update manifest has an invalid SHA-256.');
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('APK download requires a valid HTTPS URL.');
  }

  const maxBytes = 45 * 1024 * 1024;
  final client = http.Client();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/NCA-admin-update.apk');
  var received = 0;
  int? total;
  try {
    if (await file.exists()) await file.delete();
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request = http.Request('GET', uri);
        request.headers['Accept'] = 'application/vnd.android.package-archive';
        request.headers['Cache-Control'] = 'no-cache';
        if (received > 0) request.headers['Range'] = 'bytes=$received-';

        final response = await client.send(request).timeout(
          const Duration(seconds: 20),
        );
        if (response.statusCode == 416 && received > 0) {
          // The object could have changed. Re-fetch from byte zero.
          received = 0;
          total = null;
          if (await file.exists()) await file.delete();
          if (attempt == 2) throw StateError('APK range no longer valid.');
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('APK download failed (HTTP ${response.statusCode}).');
        }

        final append = response.statusCode == 206;
        if (append) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
              .firstMatch(response.headers['content-range'] ?? '');
          if (range == null || int.parse(range.group(1)!) != received) {
            throw const FormatException('APK resume response is invalid.');
          }
          total = int.parse(range.group(3)!);
        } else {
          // A server without Range support returns a complete response.
          received = 0;
          total = response.contentLength;
        }
        if (total != null && (total! <= 0 || total! > maxBytes)) {
          throw StateError('APK download size is outside the safe limit.');
        }

        final sink = file.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 20),
          )) {
            sink.add(chunk);
            received += chunk.length;
            if (received > maxBytes) {
              throw StateError('APK download exceeds safe size.');
            }
            if (total != null && total! > 0) {
              onProgress?.call((received / total!).clamp(0.0, 1.0).toDouble());
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (total != null && received != total) {
          throw StateError('APK download was incomplete.');
        }
        break;
      } catch (_) {
        // Transient network/idle failure: keep received bytes and retry with
        // a matching Content-Range. A hash mismatch never starts an install.
        if (attempt == 2) rethrow;
      }
    }

    if (received == 0) throw StateError('APK download was empty.');
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != expected) {
      throw StateError('Downloaded APK failed SHA-256 verification.');
    }
    onProgress?.call(1);
    final openResult = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (openResult.type != ResultType.done) {
      throw StateError('Could not open Android installer: ${openResult.message}');
    }
  } finally {
    client.close();
    // A failed or incomplete file must never be offered to another update.
    // Each new update starts from a fresh temporary file.
  }
}
