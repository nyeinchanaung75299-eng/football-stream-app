import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'network_endpoints.dart';

/// Select a reachable route before expensive link extraction. Probe only a
/// small public health endpoint; never race duplicate provider/browser scans.
class SourceRoutePolicy {
  SourceRoutePolicy({
    http.Client Function()? clientFactory,
    String? Function()? knownPrimary,
    DateTime Function()? now,
    this.probeTimeout = const Duration(seconds: 4),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _knownPrimary = knownPrimary ?? recentCloudflareApiBase,
       _now = now ?? DateTime.now;
  final http.Client Function() _clientFactory;
  final String? Function() _knownPrimary;
  final DateTime Function() _now;
  final Duration probeTimeout;
  String? _base;
  DateTime? _until;
  Future<String>? _probe;
  static const _cloudflare = {
    cloudflarePublicBase,
    'https://football-api.nyeinchanaung.ccwu.cc',
  };

  Future<String> preferred() {
    // A recent successful catalogue/read already proves network reachability.
    final known = _knownPrimary();
    if (_cloudflare.contains(known) &&
        (_base != vercelBackupBase ||
            _until == null ||
            !_now().isBefore(_until!)))
      return Future.value(known!);
    if (_base != null && _until != null && _now().isBefore(_until!))
      return Future.value(_base!);
    return _probe ??= _probePrimary().whenComplete(() => _probe = null);
  }

  Future<String> _probePrimary() async {
    final client = _clientFactory();
    var base = vercelBackupBase;
    try {
      final response = await client
          .get(
            Uri.parse('$cloudflarePublicBase/health'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(probeTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map &&
            (data['ok'] == true ||
                data['status'] == 'ok' ||
                data['service'] is String))
          base = cloudflarePublicBase;
      }
    } catch (_) {
      /* Operator fallback remains available without VPN. */
    } finally {
      client.close();
    }
    _base = base;
    _until = _now().add(const Duration(minutes: 1));
    return base;
  }

  void failed(String base) {
    if (!_cloudflare.contains(base)) return;
    _base = vercelBackupBase;
    _until = _now().add(const Duration(minutes: 1));
  }

  Future<T> read<T>(Future<T> Function(String base) load) async {
    final base = await preferred();
    try {
      return await load(base);
    } catch (_) {
      if (base == vercelBackupBase) rethrow;
      failed(base);
      return load(vercelBackupBase);
    }
  }
}

final sourceRoutePolicy = SourceRoutePolicy();
