bool isVisibleAdminMatch(
  Map<String, dynamic> match, {
  required String view,
  required DateTime now,
}) {
  if (match['deleted_at'] != null) return false;
  if (view == 'all') return true;

  final published = match['is_active'] == true &&
      match['is_featured'] != false &&
      (match['publish_state'] ?? 'published') == 'published';
  if (!published) return false;
  if (view == 'live') return match['is_live'] == true;

  final kickoff = DateTime.tryParse(match['kickoff_at']?.toString() ?? '');
  return match['is_live'] == true ||
      (kickoff != null && !kickoff.isBefore(now));
}

String? activeStreamUrlError({
  required bool isActive,
  required bool useWebView,
  required String streamUrl,
  required String webViewUrl,
}) {
  if (!isActive) return null;
  final value = (useWebView ? webViewUrl : streamUrl).trim();
  final label = useWebView ? 'WebView' : 'stream';
  if (value.isEmpty) return 'Paste a $label URL.';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      RegExp(r'\s').hasMatch(value)) {
    return 'Enter a valid HTTP or HTTPS $label URL.';
  }
  return null;
}
