import 'network_endpoints.dart';

const _protectedPlaybackHosts = <String>{
  'football-api.nyeinchanaung.us.ci',
  'football-api.nyeinchanaung.ccwu.cc',
  'football-public-api.nyeinchanaung75299-eng.workers.dev',
  'nca-network-backup-test.vercel.app',
  'nca25-live-relay.vercel.app',
};
const _relayTransports = {'vercel-fallback', 'cloudflare-fallback'};

/// One selectable row per actual stream. Events try Cloudflare first and keep
/// Vercel as an internal, failure-only route. Channels opt in explicitly.
/// Rewriting a protected route preserves its encrypted token, headers and DRM.
List<Map<String, dynamic>> playbackSources(
  List<Map<String, dynamic>> sources, {
  bool? useVercel,
}) {
  final output = <Map<String, dynamic>>[];
  final seen = <String>{};
  final originals = sources.where(isVisiblePlaybackLine).toList();
  for (final source in originals.isEmpty ? sources.take(1) : originals) {
    final row = Map<String, dynamic>.from(source);
    final raw = _sourceUrl(row);
    final uri = Uri.tryParse(raw);
    final protected =
        uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        _protectedPlaybackHosts.contains(uri.host) &&
        uri.path.startsWith('/p/');
    final url = protected
        ? uri
              .replace(
                host: Uri.parse(
                  useVercel == true ? vercelBackupBase : cloudflarePublicBase,
                ).host,
              )
              .toString()
        : raw;
    if (!seen.add(url)) continue;
    if (row.containsKey('url')) row['url'] = url;
    if (row.containsKey('stream_url')) row['stream_url'] = url;
    if (_relayTransports.contains(row['transport'])) {
      row['id'] = (row['id'] ?? '').toString().replaceFirst(
        RegExp(r'-(vpn-free|cloudflare-alt)$'),
        '',
      );
      row['label'] = (row['label'] ?? 'Server').toString().replaceFirst(
        RegExp(r' • (VPN-free backup|Network backup)$'),
        '',
      );
    }
    row.remove('transport');
    // Never trust route metadata from a source response. Derive the fallback
    // solely from our fixed protected hosts, retaining the opaque token.
    row.remove('routeFallbackUrl');
    if (protected && useVercel == null) {
      row['routeFallbackUrl'] = uri
          .replace(host: Uri.parse(vercelBackupBase).host)
          .toString();
    }
    output.add(row);
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
