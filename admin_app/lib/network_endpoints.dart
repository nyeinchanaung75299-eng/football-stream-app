const vercelBackupBase = 'https://nca-network-backup-test.vercel.app';
const cloudflarePublicBase = 'https://football-api.nyeinchanaung.us.ci';
const independentPublicBase =
    'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/viewer-network-api';
const viewerPublicApiKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

Map<String, String> publicApiHeaders(
  String base, {
  Map<String, String> extra = const {},
}) => {
  'Accept': 'application/json',
  if (base == independentPublicBase) 'apikey': viewerPublicApiKey,
  ...extra,
};

String independentImageUrl(String path, {String? version}) =>
    Uri.parse('$independentPublicBase$path')
        .replace(
          queryParameters: {
            'apikey': viewerPublicApiKey,
            if (version != null) 'v': version,
          },
        )
        .toString();

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

// The independent gateway exposes public catalog/guide/images only. Admin
// mutations must keep their existing authenticated FunctionGateway routes.
List<String> publicDataApiBases({bool preferVercel = false}) {
  final routes = publicApiBases(preferVercel: preferVercel);
  final at = routes.first == vercelBackupBase ? 1 : 0;
  routes.insert(at, independentPublicBase);
  return routes.toSet().toList();
}
