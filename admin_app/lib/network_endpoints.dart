const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';
const cloudflarePublicBase = 'https://football-api.nyeinchanaung.us.ci';

// Prefer the supported Cloudflare routes. Retain the operator-reachable
// Vercel route as a last fallback for networks that cannot reach Cloudflare.
List<String> publicApiBases({String? primary, bool preferVercel = false}) {
  final first = (primary ?? 'https://football-api.nyeinchanaung.us.ci')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return <String>{
    if (preferVercel) vercelBackupBase,
    if (first.isNotEmpty) first,
    'https://football-api.nyeinchanaung.ccwu.cc',
    if (!preferVercel) vercelBackupBase,
  }.toList();
}
