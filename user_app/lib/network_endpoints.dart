import 'dart:async';

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

List<String> _knownPublicApiBases({
  String? primary,
  bool preferVercel = false,
}) {
  final first = (primary ?? 'https://football-api.nyeinchanaung.us.ci')
      .trim()
      .replaceAll(RegExp(r'/+$'), '');
  return <String>{
    if (preferVercel) vercelBackupBase,
    if (first.isNotEmpty) first,
    independentPublicBase,
    'https://football-api.nyeinchanaung.ccwu.cc',
    if (!preferVercel) vercelBackupBase,
  }.toList();
}

/// Prefer the last verified public metadata route for five minutes. Keep
/// fallback hosts; never accept an arbitrary or upstream-returned URL.
List<String> publicApiBases({String? primary, bool preferVercel = false}) {
  final known = _knownPublicApiBases(
    primary: primary,
    preferVercel: preferVercel,
  );
  final last = _lastVerifiedPublicBase;
  final at = _lastVerifiedAt;
  if (last == null ||
      at == null ||
      !known.contains(last) ||
      DateTime.now().difference(at) > _publicRouteTtl) {
    return known;
  }
  return [last, ...known.where((base) => base != last)];
}

/// Metadata hedges may try both Cloudflare aliases, but a slow successful
/// response must not also spend Vercel CPU. A verified operator-only route
/// can still lead immediately. This gate is local to a single read batch.
List<Future<T> Function()> publicApiRequests<T>(
  List<String> bases,
  Future<T> Function(String base) load, {
  void Function(String base)? onHealthy,
}) {
  var pending = bases.where((base) => base != vercelBackupBase).length;
  final gate = Completer<({bool ready, T? value})>();
  final gateBackup =
      bases.isNotEmpty && bases.first != vercelBackupBase && pending > 0;
  return bases
      .map(
        (base) => () async {
          if (gateBackup && base == vercelBackupBase) {
            final result = await gate.future;
            if (result.ready) return result.value as T;
          }
          try {
            final value = await load(base);
            onHealthy?.call(base);
            if (base != vercelBackupBase && !gate.isCompleted) {
              gate.complete((ready: true, value: value));
            }
            return value;
          } catch (_) {
            if (base != vercelBackupBase &&
                --pending == 0 &&
                !gate.isCompleted) {
              gate.complete((ready: false, value: null));
            }
            rethrow;
          }
        },
      )
      .toList();
}
