import 'dart:async';

class ApkDownloadCancelled implements Exception {
  const ApkDownloadCancelled();

  @override
  String toString() => 'APK download canceled.';
}

class ApkDownloadCancellation {
  final _signal = Completer<void>();

  bool get isCancelled => _signal.isCompleted;

  void cancel() {
    if (!isCancelled) _signal.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const ApkDownloadCancelled();
  }

  Future<T> waitFor<T>(Future<T> operation) {
    throwIfCancelled();
    return Future.any<T>([
      operation,
      _signal.future.then<T>((_) => throw const ApkDownloadCancelled()),
    ]);
  }
}
