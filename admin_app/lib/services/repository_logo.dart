import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../network_endpoints.dart';

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
  if ({
    Uri.parse(cloudflarePublicBase).host,
    'football-api.nyeinchanaung.ccwu.cc',
    'football-public-api.nyeinchanaung75299-eng.workers.dev',
  }.contains(uri.host)) {
    final saved = RegExp(r'^/channel-logos/([0-9a-fA-F-]{36})$')
        .firstMatch(uri.path)
        ?.group(1);
    if (saved != null)
      return independentImageUrl(
        '/channel-logos/$saved',
        version: uri.queryParameters['v'],
      );
  }
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
    final version =
        sha256.convert(utf8.encode(value)).toString().substring(0, 24);
    return independentImageUrl('/channel-logos/$id', version: version);
  }
  return value;
}

String repositoryLogoUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final relay = {
    Uri.parse(vercelBackupBase).host,
    Uri.parse(cloudflarePublicBase).host,
    'football-api.nyeinchanaung.ccwu.cc',
    'football-public-api.nyeinchanaung75299-eng.workers.dev',
  };
  final id = uri.host == 'img.sofascore.com'
      ? RegExp(r'^/api/v1/team/(\d+)/image$').firstMatch(uri.path)?.group(1)
      : relay.contains(uri.host)
          ? RegExp(r'^/team-logos/(\d+)$').firstMatch(uri.path)?.group(1) ??
              (uri.path == '/api/channel-logo'
                  ? uri.queryParameters['team']
                  : null)
          : null;
  return id == null || !RegExp(r'^\d{1,12}$').hasMatch(id)
      ? channelLogoUrl(value)
      : independentImageUrl('/team-logos/$id');
}

List<String> logoCandidates(String value, {String? channelId}) {
  if (value.trim().isEmpty) return const [];
  final primary = channelId == null
      ? repositoryLogoUrl(value)
      : channelLogoUrl(value, channelId: channelId);
  final uri = Uri.tryParse(primary);
  final teamId = uri == null
      ? null
      : RegExp(r'/team-logos/(\d+)$').firstMatch(uri.path)?.group(1);
  final saved = uri == null
      ? null
      : RegExp(r'/channel-logos/([0-9a-fA-F-]{36})$')
          .firstMatch(uri.path)
          ?.group(1);
  final id = saved ?? channelId;
  return <String>{
    primary,
    if (teamId != null) '$cloudflarePublicBase/team-logos/$teamId',
    if (teamId != null) 'https://img.sofascore.com/api/v1/team/$teamId/image',
    if (id != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id))
      independentImageUrl('/channel-logos/$id'),
    if (id != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id))
      '$cloudflarePublicBase/channel-logos/$id',
  }.toList();
}
