import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../backend_endpoint.dart';
import '../network_endpoints.dart';

enum CheckStatus { ok, warning, failed, notConfigured }

class DiagnosticResult {
  const DiagnosticResult({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    this.ms,
  });

  final String id;
  final String title;
  final CheckStatus status;
  final String detail;
  final int? ms;

  Map<String, Object> toJson() => {
        'check': id,
        'status': status.name,
        'detail': detail,
        if (ms != null) 'ms': ms!,
      };
}

class DiagnosticsService {
  DiagnosticsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<dynamic> _getJson(String url) async {
    final response = await _client.get(Uri.parse(url), headers: const {
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  Future<DiagnosticResult> _check(
    String id,
    String title,
    Future<String> Function() action, {
    CheckStatus failureStatus = CheckStatus.failed,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return DiagnosticResult(
        id: id,
        title: title,
        status: CheckStatus.ok,
        detail: await action(),
        ms: watch.elapsedMilliseconds,
      );
    } catch (_) {
      // Never copy SDK errors, JWTs, passwords, or protected playback URLs.
      return DiagnosticResult(
        id: id,
        title: title,
        status: failureStatus,
        detail: kIsWeb
            ? 'Check failed or timed out. Network access or browser CORS can affect this test.'
            : 'Check failed or timed out on this connection.',
        ms: watch.elapsedMilliseconds,
      );
    }
  }

  Future<List<DiagnosticResult>> run({
    required void Function(DiagnosticResult) onResult,
  }) async {
    // Optional services share one bounded request. No check runs until the
    // Admin presses Run checks, and none of these checks changes stored data.
    final serviceHosts = _getJson('$vercelBackupBase/service-health');
    // Attach a listener immediately so a failed optional request is handled
    // even while the other checks are still running.
    final hosts = serviceHosts.then<dynamic>((value) => value,
        onError: (Object _) => null);

    final jobs = <Future<DiagnosticResult>>[
      _check('supabase', 'Supabase · Admin access', () async {
        final client = Supabase.instance.client;
        final user = client.auth.currentUser;
        if (user == null) throw StateError('No session');
        final profile = await client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));
        if (profile?['role'] != 'admin') throw StateError('Not an admin');
        await client
            .from('matches')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 6));
        final host = Uri.tryParse(selectedBackend ?? '')?.host;
        return 'Admin role and database read OK${host == null || host.isEmpty ? '' : ' via $host'}. Writes are not performed.';
      }),
      _check('vercel', 'Vercel · Backup API', () async {
        final health = await _getJson('$vercelBackupBase/health');
        if (health is! Map || health['ok'] != true) {
          throw const FormatException('Invalid health response');
        }
        return 'Backup API reachable on this connection.';
      }),
      _check('viewer-feed', 'Viewer · Matches & stream API', () async {
        final feed = await _getJson('$vercelBackupBase/matches');
        final rows =
            feed is List ? feed : (feed is Map ? feed['matches'] : null);
        if (rows is! List) throw const FormatException('Invalid match list');
        for (final row in rows.whereType<Map>()) {
          final id = row['id']?.toString() ?? '';
          if (id.isEmpty || (row['stream_count'] as num? ?? 0) < 1) continue;
          final streams = await _getJson(
              '$vercelBackupBase/matches/${Uri.encodeComponent(id)}/streams');
          if (streams is! Map || streams['streams'] is! List) {
            throw const FormatException('Invalid stream configuration');
          }
          final count = (streams['streams'] as List).length;
          return '${rows.length} published match(es), $count playback line(s) loaded via Vercel. Continuous playback is not tested.';
        }
        return '${rows.length} published match(es) loaded via Vercel. No match with stream lines is available to test.';
      }),
      _check('cloudflare', 'Cloudflare · Direct API', () async {
        final health =
            await _getJson('https://football-api.nyeinchanaung.us.ci/health');
        if (health is! Map || health['ok'] != true) {
          throw const FormatException('Invalid health response');
        }
        return 'Direct API reachable. The Vercel backup is available for networks that cannot reach it.';
      }, failureStatus: CheckStatus.warning),
      _check('github', 'GitHub · Match mirror', () async {
        final feed = await _getJson(
            'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/matches.json');
        if (feed is! List && (feed is! Map || feed['matches'] is! List)) {
          throw const FormatException('Invalid mirror');
        }
        return 'Mirror file reachable. Live APIs determine the current published matches.';
      }, failureStatus: CheckStatus.warning),
      _buildStatus('web-build', 'Web · Build & deployment', 'web'),
      _buildStatus('mobile-build', 'APK / iOS · Build status', 'mobile'),
      for (final entry in const {
        'viewer-web': 'Viewer website',
        'admin-web': 'Admin website',
        'posthog': 'PostHog · Analytics',
        'google-drive': 'Google Drive',
      }.entries)
        _hostResult(entry.key, entry.value, hosts),
    ];
    return Future.wait(jobs.map((job) async {
      final result = await job;
      onResult(result);
      return result;
    }));
  }

  Future<DiagnosticResult> _buildStatus(
      String id, String title, String file) async {
    try {
      final report = await _getJson(
          'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/ci/$file.json');
      if (report is! Map ||
          !const {'success', 'failure'}.contains(report['overall'])) {
        throw const FormatException('No build report');
      }
      final ok = report['overall'] == 'success';
      final date = DateTime.tryParse(report['updated_at']?.toString() ?? '');
      final sha = report['sha']?.toString() ?? '';
      final commit = RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)
          ? ' · ${sha.substring(0, 7)}'
          : '';
      return DiagnosticResult(
        id: id,
        title: title,
        status: ok ? CheckStatus.ok : CheckStatus.warning,
        detail: 'Last recorded build ${ok ? 'succeeded' : 'failed'}$commit'
            '${date == null ? '' : ' · ${date.toUtc().toIso8601String()}'}.'
            ' A newer build may still be running. This is not a device playback test.',
      );
    } catch (_) {
      return DiagnosticResult(
        id: id,
        title: title,
        status: CheckStatus.warning,
        detail: 'Build report is unavailable on this connection.',
      );
    }
  }

  Future<DiagnosticResult> _hostResult(
      String id, String title, Future<dynamic> hosts) async {
    final response = await hosts;
    final rows = response is Map ? response['results'] : null;
    Map? row;
    if (rows is List) {
      for (final item in rows.whereType<Map>()) {
        if (item['service'] == id) row = item;
      }
    }
    final reachable = row?['reachable'] == true;
    final ms = (row?['ms'] as num?)?.toInt();
    if (id == 'google-drive') {
      return DiagnosticResult(
        id: id,
        title: title,
        status: CheckStatus.notConfigured,
        detail: 'Not connected to this app. ChatGPT plugin access is separate'
            '${reachable ? '; service host reachable via Vercel' : ''}.',
        ms: ms,
      );
    }
    if (id == 'posthog') {
      final ready = AnalyticsService.isReady;
      return DiagnosticResult(
        id: id,
        title: title,
        status: ready && reachable ? CheckStatus.ok : CheckStatus.warning,
        detail: 'SDK ${ready ? 'ready' : 'not ready'}; service host '
            '${reachable ? 'reachable' : 'unavailable'} via Vercel. Event delivery is not verified. Analytics does not block the app.',
        ms: ms,
      );
    }
    // These web pages are checked from Vercel, not from the phone browser.
    final httpCode = row?['http'] as num?;
    final ok =
        reachable && httpCode != null && httpCode >= 200 && httpCode < 300;
    return DiagnosticResult(
      id: id,
      title: title,
      status: ok ? CheckStatus.ok : CheckStatus.warning,
      detail: ok
          ? 'HTTP ${httpCode.toInt()} from Vercel. Phone access and UI behavior require a browser test.'
          : 'Website check from Vercel failed or timed out.',
      ms: ms,
    );
  }
}
