const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';

List<String> publicApiBases({String? primary, bool preferVercel = false}) {
  final first = (primary ?? 'https://football-api.nyeinchanaung.us.ci')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return <String>{
    if (preferVercel) vercelBackupBase,
    if (first.isNotEmpty) first,
    vercelBackupBase,
    'https://football-api.nyeinchanaung.ccwu.cc',
    'https://football-public-api.nyeinchanaung75299-eng.workers.dev',
  }.toList();
}
