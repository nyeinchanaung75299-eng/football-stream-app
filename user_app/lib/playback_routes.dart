import 'network_endpoints.dart';

const _protectedPlaybackHosts = <String>{
  'football-api.nyeinchanaung.us.ci',
  'football-api.nyeinchanaung.ccwu.cc',
  'football-public-api.nyeinchanaung75299-eng.workers.dev',
};

/// Keeps the direct Cloudflare stream first and places a Vercel relay copy
/// immediately after it. Players only open the relay after the direct source
/// fails, so a healthy stream never pays for the extra network hop.
List<Map<String, dynamic>> addVpnFreePlaybackFallbacks(
  List<Map<String, dynamic>> sources,
) {
  final output = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final source in sources) {
    final direct = Map<String, dynamic>.from(source);
    final key = _sourceUrl(direct);
    if (key.isEmpty || seen.add(key)) output.add(direct);

    final uri = Uri.tryParse(key);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_protectedPlaybackHosts.contains(uri.host) ||
        !uri.path.startsWith('/p/')) {
      continue;
    }

    final fallbackUrl = uri
        .replace(scheme: 'https', host: Uri.parse(vercelBackupBase).host)
        .toString();
    if (!seen.add(fallbackUrl)) continue;

    final fallback = Map<String, dynamic>.from(direct);
    if (fallback.containsKey('url')) fallback['url'] = fallbackUrl;
    if (fallback.containsKey('stream_url')) {
      fallback['stream_url'] = fallbackUrl;
    }
    fallback['id'] = '${fallback['id'] ?? 'stream'}-vpn-free';
    final label = (fallback['label'] ?? 'Server').toString().trim();
    fallback['label'] = '${label.isEmpty ? 'Server' : label} • VPN-free backup';
    fallback['transport'] = 'vercel-fallback';
    output.add(fallback);
  }

  return output;
}

String _sourceUrl(Map<String, dynamic> source) =>
    (source['url'] ?? source['stream_url'] ?? '').toString().trim();

/// Only primary sources belong in visible line pickers. Network relay copies
/// remain in the player session for automatic failover if direct playback fails.
bool isVisiblePlaybackLine(Map<String, dynamic> source) =>
    source['transport']?.toString() != 'vercel-fallback';

List<int> visiblePlaybackIndices(List<Map<String, dynamic>> sources) => [
  for (var index = 0; index < sources.length; index++)
    if (isVisiblePlaybackLine(sources[index])) index,
];
