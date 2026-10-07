import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update_cancellation.dart';

Future<void> downloadAndInstallApk(
  String url, {
  required String expectedSha256,
  void Function(double value)? onProgress,
  ApkDownloadCancellation? cancellation,
  http.Client? client,
  Future<Directory> Function()? temporaryDirectory,
  Future<OpenResult> Function(String path)? openApk,
  Duration headerTimeout = const Duration(seconds: 20),
  Duration bodyIdleTimeout = const Duration(seconds: 20),
}) async {
  final downloadClient = client ?? http.Client();
  final cancel = cancellation ?? ApkDownloadCancellation();

  IOSink? sink;
  StreamSubscription<List<int>>? subscription;
  File? file;
  var completed = false;
  try {
    cancel.throwIfCancelled();
    final expected = expectedSha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw const FormatException(
        'Update manifest is missing a valid SHA-256.',
      );
    }
    final request = http.Request('GET', Uri.parse(url));
    request.headers['Accept'] = 'application/vnd.android.package-archive';
    request.headers['Cache-Control'] = 'no-cache';

    final response = await cancel.waitFor(
      downloadClient.send(request).timeout(headerTimeout),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'APK download failed (HTTP ${response.statusCode}).',
      );
    }

    final dir = await cancel.waitFor(
      (temporaryDirectory ?? getTemporaryDirectory)(),
    );
    file = File('${dir.path}/NCA-update.apk');
    if (await file.exists()) {
      await file.delete();
    }

    cancel.throwIfCancelled();
    final output = file.openWrite();
    sink = output;
    // Listen for file-system errors immediately, including during a stalled
    // network response, so neither the sink nor its errors are left dangling.
    final body = Completer<void>();
    void fail(Object error, StackTrace stack) {
      if (!body.isCompleted) body.completeError(error, stack);
    }
    unawaited(output.done.then<void>((_) {}, onError: fail));
    final total = response.contentLength ?? 0;
    var received = 0;

    subscription = response.stream.timeout(bodyIdleTimeout).listen(
      (chunk) {
        if (cancel.isCancelled || body.isCompleted) return;
        output.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      },
      onError: fail,
      onDone: () {
        if (!body.isCompleted) body.complete();
      },
    );
    await cancel.waitFor(body.future);
    if (total > 0 && received != total) {
      throw const FormatException('APK download ended before completion.');
    }
    await output.flush();
    await output.close();
    sink = null;
    onProgress?.call(1);

    final digest = await cancel.waitFor(sha256.bind(file.openRead()).first);
    if (digest.toString().toLowerCase() != expected) {
      throw StateError('Downloaded APK failed SHA-256 verification.');
    }
    cancel.throwIfCancelled();
    final openResult = await (openApk ??
        (path) => OpenFilex.open(
              path,
              type: 'application/vnd.android.package-archive',
            ))(file.path);
    if (openResult.type != ResultType.done) {
      throw StateError(
        'Could not open the Android installer: ${openResult.message}',
      );
    }
    completed = true;
  } finally {
    downloadClient.close();
    try {
      await subscription?.cancel();
    } finally {
      try {
        await sink?.close();
      } finally {
        if (!completed && file != null && await file.exists()) {
          await file.delete();
        }
      }
    }
  }
}
