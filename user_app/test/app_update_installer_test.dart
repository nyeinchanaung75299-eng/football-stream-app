import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import 'package:football_viewer/app_update_cancellation.dart';
import 'package:football_viewer/app_update_installer_io.dart';

class _DownloadClient extends http.BaseClient {
  _DownloadClient(this.respond);

  final Future<http.StreamedResponse> Function() respond;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => respond();

  @override
  void close() => closed = true;
}

void main() {
  late Directory directory;
  const bytes = <int>[1, 2, 3, 4, 5, 6];
  final digest = sha256.convert(bytes).toString();

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nca-update-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('opens the installer only after the full APK passes SHA-256', () async {
    final client = _DownloadClient(() async => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 3), bytes.sublist(3)]),
          200,
          contentLength: bytes.length,
        ));
    var opened = false;
    await downloadAndInstallApk(
      'https://example.test/update.apk',
      expectedSha256: digest,
      client: client,
      temporaryDirectory: () async => directory,
      openApk: (path) async {
        expect(await File(path).readAsBytes(), bytes);
        opened = true;
        return OpenResult();
      },
    );
    expect(opened, isTrue);
    expect(client.closed, isTrue);
    expect(await File('${directory.path}/NCA-update.apk').exists(), isTrue);
  });

  test('rejects a hash mismatch and removes the APK without opening it', () async {
    final client = _DownloadClient(() async => http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length,
        ));
    var opened = false;
    await expectLater(
      downloadAndInstallApk(
        'https://example.test/update.apk',
        expectedSha256: sha256.convert([99]).toString(),
        client: client,
        temporaryDirectory: () async => directory,
        openApk: (_) async {
          opened = true;
          return OpenResult();
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(opened, isFalse);
    expect(client.closed, isTrue);
    expect(await directory.list().toList(), isEmpty);
  });

  test('times out a response that stalls after its first body chunk', () async {
    var unsubscribed = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        unsubscribed = true;
      },
    )..add(bytes.sublist(0, 2));
    final client = _DownloadClient(() async => http.StreamedResponse(
          body.stream,
          200,
          contentLength: bytes.length,
        ));
    await expectLater(
      downloadAndInstallApk(
        'https://example.test/update.apk',
        expectedSha256: digest,
        client: client,
        temporaryDirectory: () async => directory,
        bodyIdleTimeout: const Duration(milliseconds: 50),
        openApk: (_) async => fail('A stalled APK must not be installed.'),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.closed, isTrue);
    expect(unsubscribed, isTrue);
    expect(await directory.list().toList(), isEmpty);
    await body.close();
  });

  test('cancel during the body aborts and removes the partial APK', () async {
    final firstChunk = Completer<void>();
    var unsubscribed = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        unsubscribed = true;
      },
    )..add(bytes.sublist(0, 2));
    final cancel = ApkDownloadCancellation();
    final client = _DownloadClient(() async => http.StreamedResponse(
          body.stream,
          200,
          contentLength: bytes.length,
        ));
    final download = downloadAndInstallApk(
      'https://example.test/update.apk',
      expectedSha256: digest,
      cancellation: cancel,
      client: client,
      temporaryDirectory: () async => directory,
      onProgress: (_) {
        if (!firstChunk.isCompleted) firstChunk.complete();
      },
      openApk: (_) async => fail('A canceled APK must not be installed.'),
    );
    final failure = expectLater(download, throwsA(isA<ApkDownloadCancelled>()));
    await firstChunk.future;
    cancel.cancel();
    await failure;
    expect(client.closed, isTrue);
    expect(unsubscribed, isTrue);
    expect(await directory.list().toList(), isEmpty);
    await body.close();
  });

  test('cancel while waiting for headers closes the HTTP client', () async {
    final cancel = ApkDownloadCancellation();
    final headers = Completer<http.StreamedResponse>();
    final client = _DownloadClient(() => headers.future);
    final download = downloadAndInstallApk(
      'https://example.test/update.apk',
      expectedSha256: digest,
      cancellation: cancel,
      client: client,
      headerTimeout: const Duration(milliseconds: 100),
      temporaryDirectory: () async => directory,
      openApk: (_) async => fail('A canceled APK must not be installed.'),
    );
    final failure = expectLater(download, throwsA(isA<ApkDownloadCancelled>()));
    cancel.cancel();
    await failure;
    expect(client.closed, isTrue);
    expect(await directory.list().toList(), isEmpty);
    headers.complete(http.StreamedResponse(const Stream.empty(), 200));
  });

  test('rejects a truncated body even when the available bytes hash matches',
      () async {
    final client = _DownloadClient(() async => http.StreamedResponse(
          Stream.value(bytes),
          200,
          contentLength: bytes.length + 1,
        ));
    await expectLater(
      downloadAndInstallApk(
        'https://example.test/update.apk',
        expectedSha256: digest,
        client: client,
        temporaryDirectory: () async => directory,
        openApk: (_) async => fail('A truncated APK must not be installed.'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(client.closed, isTrue);
    expect(await directory.list().toList(), isEmpty);
  });
}
