const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';

// Viewer/Admin public APIs prefer the reachable Vercel relay. Cloudflare stays as fallback.
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
