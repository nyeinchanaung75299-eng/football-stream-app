const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';

// Keep only currently supported public routes in the new Viewer build.
// The disabled workers.dev alias is not a useful automatic hedge.
String? _lastVerifiedPublicBase;
DateTime? _lastVerifiedAt;
const _publicRouteTtl = Duration(minutes: 5);

void rememberVerifiedPublicApiBase(String base) {
  if (_knownPublicApiBases().contains(base)) {
    _lastVerifiedPublicBase = base;
    _lastVerifiedAt = DateTime.now();
  }
}

List<String> _knownPublicApiBases({String? primary, bool preferVercel = true}) {
  final first = (primary ?? 'https://football-api.nyeinchanaung.us.ci')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return <String>{
    if (preferVercel) vercelBackupBase,
    if (first.isNotEmpty) first,
    if (!preferVercel) vercelBackupBase,
    'https://football-api.nyeinchanaung.ccwu.cc',
  }.toList();
}

/// Prefer the last verified public metadata route for five minutes. Keep
/// fallback hosts; never accept an arbitrary or upstream-returned URL.
List<String> publicApiBases({String? primary, bool preferVercel = true}) {
  final known = _knownPublicApiBases(
      primary: primary, preferVercel: preferVercel);
  final last = _lastVerifiedPublicBase;
  final at = _lastVerifiedAt;
  if (last == null || at == null || !known.contains(last) ||
      DateTime.now().difference(at) > _publicRouteTtl) {
    return known;
  }
  return [last, ...known.where((base) => base != last)];
}
