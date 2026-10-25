/// Safe explanatory messages for stream preview errors.
///
/// A detected URL is not necessarily playable. In particular, third-party HLS
/// URLs may be signed and short-lived or enforce playback restrictions.
String previewUrlForDisplay(String rawUrl) {
  final url = Uri.tryParse(rawUrl);
  if (url == null || url.host.isEmpty) return 'Stream URL';
  // Signed query parameters are credentials in some streaming systems:
  // never display them in screenshots or generic error messages.
  final safe = '${url.scheme}://${url.authority}${url.path}';
  return url.hasQuery ? '$safe?… (parameters hidden)' : safe;
}

bool hasTemporaryLinkParameters(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasQuery) return false;
  final keys = uri.queryParameters.keys.map((k) => k.toLowerCase()).toSet();
  return keys.any(
    (key) => {
      't', '_', 'expires', 'exp', 'expiry', 'signature', 'sig', 'token',
      'auth', 'key',
    }.contains(key),
  );
}

String explainPreviewError(Object? error, {required bool isWeb}) {
  final detail = error?.toString().toUpperCase() ?? '';
  if (detail.contains('MEDIA_ERR_SRC_NOT_SUPPORTED')) {
    return 'The browser could not load this media source. The URL may no longer '
        'be valid, the streaming server may reject direct playback, or the '
        'playlist/codec may be unsupported. This error alone cannot identify '
        'which cause applies.';
  }
  if (detail.contains('MEDIA_ERR_NETWORK') ||
      detail.contains('SOCKETEXCEPTION') ||
      detail.contains('CLIENTEXCEPTION')) {
    return 'The player could not obtain the media over the network. Verify '
        'connectivity and whether the source server permits playback.';
  }
  if (detail.contains('TIMEOUTEXCEPTION')) {
    return 'The stream did not initialize before the timeout. It may be '
        'unreachable or slow to respond.';
  }
  if (detail.contains('MEDIA_ERR_DECODE')) {
    return 'The media was received but could not be decoded by this device.';
  }
  return isWeb
      ? 'The browser could not play this stream. An accessible, supported '
        'media URL is required, and some websites restrict direct playback.'
      : 'The player could not start this stream. Check its source, validity '
        'and supported encoding.';
}

/// Launch only a genuine source website page, never the extracted media URL.
/// Browsers must open the source in its own origin so its normal player,
/// cookies and authorization remain controlled by the source website.
Uri? sourcePlayerPage(String rawReferer) {
  final uri = Uri.tryParse(rawReferer.trim());
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}
