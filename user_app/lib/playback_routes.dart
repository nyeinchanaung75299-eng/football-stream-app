import 'network_endpoints.dart';

const _protectedPlaybackHosts = <String>{
  'football-api.nyeinchanaung.us.ci',
  'football-api.nyeinchanaung.ccwu.cc',
  'football-public-api.nyeinchanaung75299-eng.workers.dev',
  'nca-network-backup-test.vercel.app',
};
const _relayTransports = {'vercel-fallback', 'cloudflare-fallback'};

/// Try supported Cloudflare aliases before spending Vercel media CPU. The
/// operator relay remains the last option when both aliases are unreachable.
/// Only the hostname changes: tokens, request headers and DRM stay intact.
List<Map<String, dynamic>> addVpnFreePlaybackFallbacks(
  List<Map<String, dynamic>> sources,
) {
  final output = <Map<String, dynamic>>[];
  final seen = <String>{};
  final originals = sources
      .where((s) => !_relayTransports.contains(s['transport']))
      .toList();
  for (final source in originals.isEmpty ? sources.take(1) : originals) {
    final direct = Map<String, dynamic>.from(source);
    final uri = Uri.tryParse(_sourceUrl(direct));
    final protected =
        uri != null &&
        uri.scheme == 'https' &&
        _protectedPlaybackHosts.contains(uri.host) &&
        uri.path.startsWith('/p/');
    if (!protected) {
      if (seen.add(_sourceUrl(direct))) output.add(direct);
      continue;
    }
    final hosts = <String>{
      if (uri.host != Uri.parse(vercelBackupBase).host &&
          !uri.host.endsWith('.workers.dev'))
        uri.host,
      Uri.parse(cloudflarePublicBase).host,
      'football-api.nyeinchanaung.ccwu.cc',
      Uri.parse(vercelBackupBase).host,
    };
    var first = true;
    for (final host in hosts) {
      final url = uri.replace(host: host).toString();
      if (!seen.add(url)) continue;
      final row = Map<String, dynamic>.from(direct);
      if (row.containsKey('url')) row['url'] = url;
      if (row.containsKey('stream_url')) row['stream_url'] = url;
      if (first) {
        row.remove('transport');
      } else {
        final vercel = host == Uri.parse(vercelBackupBase).host;
        row['transport'] = vercel ? 'vercel-fallback' : 'cloudflare-fallback';
        row['id'] =
            '${direct['id'] ?? 'stream'}-${vercel ? 'vpn-free' : 'cloudflare-alt'}';
        row['label'] =
            '${direct['label'] ?? 'Server'} • ${vercel ? 'VPN-free backup' : 'Network backup'}';
      }
      output.add(row);
      first = false;
    }
  }
  return output;
}

String _sourceUrl(Map<String, dynamic> source) =>
    (source['url'] ?? source['stream_url'] ?? '').toString().trim();

bool isVisiblePlaybackLine(Map<String, dynamic> source) =>
    !_relayTransports.contains(source['transport']);

List<int> visiblePlaybackIndices(List<Map<String, dynamic>> sources) => [
  for (var index = 0; index < sources.length; index++)
    if (isVisiblePlaybackLine(sources[index])) index,
];
