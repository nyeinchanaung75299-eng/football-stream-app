import 'package:flutter/services.dart';

class NativePlayer {
  static const MethodChannel _channel = MethodChannel('football_stream/native_player');

  static Future<void> open({
    required String url,
    required String streamType,
    String? referer,
    String? origin,
    String? keyId,
    String? keyData,
    String? title,
  }) async {
    await _channel.invokeMethod<void>('openPlayer', {
      'url': url,
      'streamType': streamType,
      'referer': referer ?? '',
      'origin': origin ?? '',
      'keyId': keyId ?? '',
      'keyData': keyData ?? '',
      'title': title ?? 'Football Live',
    });
  }
}
