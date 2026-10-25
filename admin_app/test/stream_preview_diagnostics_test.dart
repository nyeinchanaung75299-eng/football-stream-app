import 'package:flutter_test/flutter_test.dart';

import '../lib/services/stream_preview_diagnostics.dart';

void main() {
  test('hides signed URL query parameters from screen display', () {
    const raw = 'https://cdn.example.org/live/index.m3u8?t=123.signature&_=456';
    expect(
      previewUrlForDisplay(raw),
      'https://cdn.example.org/live/index.m3u8?… (parameters hidden)',
    );
    expect(previewUrlForDisplay(raw).contains('signature'), isFalse);
  });

  test('does not flag ordinary query values as signed', () {
    expect(hasTemporaryLinkParameters(
      'https://cdn.example.org/video.mp4?quality=720',
    ), isFalse);
  });

  test('flags possible short-lived HLS signatures without assuming expiry', () {
    expect(hasTemporaryLinkParameters(
      'https://cdn.example.org/index.m3u8?t=123&_ =456',
    ), isTrue);
    expect(hasTemporaryLinkParameters(
      'https://cdn.example.org/master.m3u8?token=abc',
    ), isTrue);
  });

  test('browser format error explanation is not a false expiry claim', () {
    final message = explainPreviewError(
      'PlatformException(MEDIA_ERR_SRC_NOT_SUPPORTED, unsupported, null)',
      isWeb: true,
    );
    expect(message, contains('could not load this media source'));
    expect(message, contains('cannot identify'));
  });

  test('network and timeout errors are distinguished', () {
    expect(explainPreviewError('MEDIA_ERR_NETWORK', isWeb: true),
        contains('network'));
    expect(explainPreviewError('TimeoutException', isWeb: true),
        contains('timeout'));
  });
}
