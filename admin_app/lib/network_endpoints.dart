const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';

// Myanmar operator routes can time out on Cloudflare even when GitHub and
// Vercel are reachable. Use Vercel for metadata/Admin traffic by default and
// keep every existing Cloudflare host as an automatic VPN-capable fallback.
List<String> publicApiBases({String? primary, bool preferVercel = true}) {
  final first = (primary ?? 'https://football-api.nyeinchanaung.us.ci')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return <String>{
    if (preferVercel) vercelBackupBase,
    if (first.isNotEmpty) first,
    if (!preferVercel) vercelBackupBase,
    'https://football-api.nyeinchanaung.ccwu.cc',
    'https://football-public-api.nyeinchanaung75299-eng.workers.dev',
  }.toList();
}
