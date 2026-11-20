const vercelBackupBase = 'https://nca25-live-relay.vercel.app';
const legacyVercelBase = 'https://nca-network-backup-test.vercel.app';
const cloudflarePublicBase = 'https://football-api.nyeinchanaung.us.ci';
const independentPublicBase =
    'https://woggzixprvyjnfjzsglz.supabase.co/functions/v1/viewer-network-api';
const viewerPublicApiKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

Map<String, String> publicApiHeaders(
  String base, {
  Map<String, String> extra = const {},
}) =>
    {
      'Accept': 'application/json',
      if (base == independentPublicBase) 'apikey': viewerPublicApiKey,
      ...extra,
    };

String independentImageUrl(String path, {String? version}) =>
    Uri.parse('$independentPublicBase$path').replace(
      queryParameters: {
        'apikey': viewerPublicApiKey,
        if (version != null) 'v': version,
      },
    ).toString();

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
  // Auth reachability does not determine public guide/catalog reachability.
  // The independent metadata gateway works even when Auth needs Vercel.
  return <String>{independentPublicBase, ...publicApiBases()}.toList();
}

String? _verifiedCloudflareBase;
DateTime? _verifiedCloudflareAt;
void rememberVerifiedCloudflareBase(String base) {
  if (!const {
    cloudflarePublicBase,
    'https://football-api.nyeinchanaung.ccwu.cc'
  }.contains(base)) return;
  _verifiedCloudflareBase = base;
  _verifiedCloudflareAt = DateTime.now();
}

String? recentCloudflareApiBase() => _verifiedCloudflareAt != null &&
        DateTime.now().difference(_verifiedCloudflareAt!) <
            const Duration(minutes: 2)
    ? _verifiedCloudflareBase
    : null;
