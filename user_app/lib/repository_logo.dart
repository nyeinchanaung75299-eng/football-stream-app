import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'network_endpoints.dart';

/// Static, reviewed channel assets need no function invocation or relay.
bool _staticChannelAsset(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'raw.githubusercontent.com' &&
    uri.userInfo.isEmpty &&
    uri.path.startsWith('/nyeinchanaung75299-eng/football-stream-app/') &&
    uri.path.contains('/public/channel-logos/') &&
    RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(uri.path);

String channelLogoUrl(String value, {String? channelId}) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  if (_staticChannelAsset(uri)) return value;
  var id = channelId;
  if (uri.host == Uri.parse(vercelBackupBase).host &&
      uri.path == '/api/channel-logo') {
    final nested = Uri.tryParse(
      uri.queryParameters['v'] ?? uri.queryParameters['url'] ?? '',
    );
    if (nested != null && _staticChannelAsset(nested)) return nested.toString();
    id ??= uri.queryParameters['id'];
  } else {
    // Existing provider CDNs already avoid Vercel. Keep their browser path:
    // some image providers reject server-to-server image requests.
    return value;
  }
  if (id != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
    final version = sha256
        .convert(utf8.encode(value))
        .toString()
        .substring(0, 24);
    return '$cloudflarePublicBase/channel-logos/$id?v=$version';
  }
  return value;
}

String repositoryLogoUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final id = uri.host == 'img.sofascore.com'
      ? RegExp(r'^/api/v1/team/(\d+)/image$').firstMatch(uri.path)?.group(1)
      : uri.host == Uri.parse(vercelBackupBase).host
      ? RegExp(r'^/team-logos/(\d+)$').firstMatch(uri.path)?.group(1) ??
            uri.queryParameters['team']
      : null;
  return id == null || !RegExp(r'^\d{1,12}$').hasMatch(id)
      ? channelLogoUrl(value)
      : '$cloudflarePublicBase/team-logos/$id';
}
