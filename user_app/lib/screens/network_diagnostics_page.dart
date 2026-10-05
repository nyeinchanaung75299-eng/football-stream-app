import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_update_service.dart';

class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  static const _socoUrl = 'https://m.sutbongtv.com/match.html';
  static const _publicApiUrls = <String>[
    'https://football-api.nyeinchanaung.us.ci',
    'https://football-public-api.nyeinchanaung75299-eng.workers.dev',
  ];
  static const _mirrorUrl =
      'https://raw.githubusercontent.com/'
      'nyeinchanaung75299-eng/football-stream-app/'
      'feed/public/matches.json';
  static const _mirrorStreamsUrl =
      'https://raw.githubusercontent.com/'
      'nyeinchanaung75299-eng/football-stream-app/'
      'feed/public/streams.json';

  Uri _mirrorMatchesUri() =>
      kIsWeb ? Uri.base.resolve('matches.json') : Uri.parse(_mirrorUrl);

  Uri _mirrorStreamsUri() =>
      kIsWeb ? Uri.base.resolve('streams.json') : Uri.parse(_mirrorStreamsUrl);

  bool _running = false;
  final List<_DiagResult> _results = [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
    });

    await _checkSupabase();
    await _checkPublicApi();
    await _checkMirror();
    await _checkSoco();
    await _checkStreams();

    if (mounted) setState(() => _running = false);
  }

  void _add(_DiagResult result) {
    if (!mounted) return;
    setState(() => _results.add(result));
  }

  Future<void> _checkSupabase() async {
    final started = DateTime.now();
    try {
      await Supabase.instance.client
          .from('matches')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 8));

      _add(
        _DiagResult(
          title: 'Supabase',
          detail: 'Direct connection OK • ${_ms(started)} ms',
          status: _DiagStatus.ok,
        ),
      );
    } on TimeoutException {
      _add(
        const _DiagResult(
          title: 'Supabase',
          detail: 'Timed out. This network may be blocking or delaying the API.',
          status: _DiagStatus.fail,
        ),
      );
    } catch (e) {
      _add(
        _DiagResult(
          title: 'Supabase',
          detail: 'Connection failed: ${_shortError(e)}',
          status: _DiagStatus.fail,
        ),
      );
    }
  }

  Future<void> _checkPublicApi() async {
    Object? lastError;
    for (final base in _publicApiUrls) {
      final started = DateTime.now();
      final client = http.Client();
      try {
        final response = await client
            .get(
              Uri.parse('$base/health'),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          _add(
            _DiagResult(
              title: 'Cloudflare public API',
              detail:
                  'VPN-free fallback OK • ${Uri.parse(base).host} • '
                  'HTTP ${response.statusCode} • ${_ms(started)} ms',
              status: _DiagStatus.ok,
            ),
          );
          return;
        }
        lastError = Exception('HTTP ${response.statusCode}');
      } catch (e) {
        lastError = e;
      } finally {
        client.close();
      }
    }

    _add(
      _DiagResult(
        title: 'Cloudflare public API',
        detail: 'Both API endpoints failed: ${_shortError(lastError ?? 'unavailable')}',
        status: _DiagStatus.fail,
      ),
    );
  }

  Future<void> _checkMirror() async {
    final started = DateTime.now();
    final client = http.Client();
    try {
      final response = await client
          .get(
            _mirrorMatchesUri(),
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 8));

      final ok = response.statusCode >= 200 &&
          response.statusCode < 300 &&
          response.body.trim().startsWith('[');

      _add(
        _DiagResult(
          title: 'GitHub match mirror',
          detail: ok
              ? 'VPN-free fallback OK • HTTP ${response.statusCode} • ${_ms(started)} ms'
              : 'Mirror reached but feed is unavailable • HTTP ${response.statusCode}',
          status: ok ? _DiagStatus.ok : _DiagStatus.fail,
        ),
      );
    } on TimeoutException {
      _add(
        const _DiagResult(
          title: 'GitHub match mirror',
          detail: 'Mirror timed out on this network.',
          status: _DiagStatus.fail,
        ),
      );
    } catch (e) {
      _add(
        _DiagResult(
          title: 'GitHub match mirror',
          detail: 'Mirror failed: ${_shortError(e)}',
          status: _DiagStatus.fail,
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _checkSoco() async {
    final started = DateTime.now();
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(_socoUrl),
            headers: const {'Accept': 'text/html,*/*'},
          )
          .timeout(const Duration(seconds: 8));

      final ok = response.statusCode >= 200 && response.statusCode < 400;
      _add(
        _DiagResult(
          title: 'Soco source',
          detail: ok
              ? 'Direct connection OK • HTTP ${response.statusCode} • ${_ms(started)} ms'
              : 'Host reached but returned HTTP ${response.statusCode}',
          status: ok ? _DiagStatus.ok : _DiagStatus.warning,
        ),
      );
    } on TimeoutException {
      _add(
        const _DiagResult(
          title: 'Soco source',
          detail: 'Timed out without VPN on this network.',
          status: _DiagStatus.fail,
        ),
      );
    } catch (e) {
      _add(
        _DiagResult(
          title: 'Soco source',
          detail: kIsWeb
              ? 'Browser could not fetch it directly. This can be CORS or network blocking.'
              : 'Direct connection failed: ${_shortError(e)}',
          status: kIsWeb ? _DiagStatus.warning : _DiagStatus.fail,
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _checkStreams() async {
    final samples = <Map<String, dynamic>>[];
    Object? supabaseError;

    try {
      final matches = await Supabase.instance.client
          .from('matches')
          .select(
            'id,home_team,away_team,stream_links('
            'label,stream_type,stream_url,referer,origin,is_active,health_status'
            ')',
          )
          .eq('is_active', true)
          .eq('publish_state', 'published')
          .eq('is_featured', true)
          .limit(3)
          .timeout(const Duration(seconds: 6));

      for (final rawMatch in matches) {
        final match = Map<String, dynamic>.from(rawMatch as Map);
        final links = List<Map<String, dynamic>>.from(
          match['stream_links'] ?? const [],
        ).where((x) => x['is_active'] == true).toList()
          ..sort((a, b) => _formatRank(a).compareTo(_formatRank(b)));

        for (final link in links) {
          final url = (link['stream_url'] ?? '').toString().trim();
          if (url.isEmpty) continue;
          samples.add({
            ...link,
            'match': '${match['home_team']} vs ${match['away_team']}',
          });
          if (samples.length >= 5) break;
        }
        if (samples.length >= 5) break;
      }
    } catch (e) {
      supabaseError = e;
    }

    if (samples.isEmpty) {
      final client = http.Client();
      try {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final response = await client
            .get(
              _mirrorStreamsUri().replace(
                queryParameters: {'t': stamp.toString()},
              ),
              headers: const {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final rawLinks = entry.value;
              if (rawLinks is! List) continue;
              final links = rawLinks
                  .map((raw) => Map<String, dynamic>.from(raw as Map))
                  .where((x) => x['is_active'] == true)
                  .toList()
                ..sort((a, b) => _formatRank(a).compareTo(_formatRank(b)));

              for (final link in links) {
                final url = (link['stream_url'] ?? '').toString().trim();
                if (url.isEmpty) continue;
                samples.add({
                  ...link,
                  'match': 'GitHub fallback',
                });
                if (samples.length >= 5) break;
              }
              if (samples.length >= 5) break;
            }
          }
        }

        if (samples.isNotEmpty) {
          _add(
            _DiagResult(
              title: 'Stream list fallback',
              detail:
                  'Supabase stream list unavailable; GitHub fallback loaded • '
                  'HTTP ${response.statusCode}',
              status: _DiagStatus.ok,
            ),
          );
        }
      } catch (_) {
        // Report the combined failure below.
      } finally {
        client.close();
      }
    }

    if (samples.isEmpty) {
      _add(
        _DiagResult(
          title: 'Stream tests',
          detail: supabaseError == null
              ? 'No active stream URL is available to test.'
              : 'Could not load stream samples from Supabase or GitHub fallback: '
                  '${_shortError(supabaseError)}',
          status: supabaseError == null
              ? _DiagStatus.warning
              : _DiagStatus.fail,
        ),
      );
      return;
    }

    for (final sample in samples) {
      await _probeStream(sample);
    }
  }

  Future<void> _probeStream(Map<String, dynamic> sample) async {
    final urlText = (sample['stream_url'] ?? '').toString().trim();
    final uri = Uri.tryParse(urlText);
    if (uri == null || !uri.hasScheme) return;

    final type = _streamType(sample);
    final label = (sample['label'] ?? 'Line').toString();
    final host = uri.host.isEmpty ? 'stream host' : uri.host;
    final started = DateTime.now();
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = '*/*'
        ..headers['Range'] = 'bytes=0-1024';

      if (!kIsWeb) {
        final referer = (sample['referer'] ?? '').toString().trim();
        final origin = (sample['origin'] ?? '').toString().trim();
        if (referer.isNotEmpty) request.headers['Referer'] = referer;
        if (origin.isNotEmpty) request.headers['Origin'] = origin;
      }

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));

      final code = response.statusCode;
      final ok = code == 200 || code == 206 || (code >= 300 && code < 400);

      // Read only the first response chunk. This is reachability testing,
      // not video relaying or downloading.
      try {
        await response.stream.first.timeout(const Duration(seconds: 2));
      } catch (_) {}

      _add(
        _DiagResult(
          title: '$label • $type',
          detail: ok
              ? '$host reachable • HTTP $code • ${_ms(started)} ms'
              : '$host reached but returned HTTP $code',
          status: ok
              ? _DiagStatus.ok
              : (code == 401 || code == 403
                  ? _DiagStatus.warning
                  : _DiagStatus.fail),
        ),
      );
    } on TimeoutException {
      _add(
        _DiagResult(
          title: '$label • $type',
          detail: '$host timed out on this network.',
          status: _DiagStatus.fail,
        ),
      );
    } catch (e) {
      _add(
        _DiagResult(
          title: '$label • $type',
          detail: kIsWeb
              ? '$host browser test failed. CORS or network access may be blocking it.'
              : '$host direct test failed: ${_shortError(e)}',
          status: kIsWeb ? _DiagStatus.warning : _DiagStatus.fail,
        ),
      );
    } finally {
      client.close();
    }
  }

  int _formatRank(Map<String, dynamic> row) {
    final type = _streamType(row).toLowerCase();
    if (type == 'hls') return 0;
    if (type == 'dash') return 1;
    if (type == 'mp4') return 2;
    if (type == 'auto') return 3;
    if (type == 'flv') return 4;
    return 5;
  }

  String _streamType(Map<String, dynamic> row) {
    final declared =
        (row['stream_type'] ?? 'auto').toString().toLowerCase();
    final url = (row['stream_url'] ?? '').toString().toLowerCase();

    if (declared == 'hls' || declared == 'm3u8' || url.contains('.m3u8')) {
      return 'HLS';
    }
    if (declared == 'dash' || declared == 'mpd' || url.contains('.mpd')) {
      return 'DASH';
    }
    if (declared == 'flv' || url.contains('.flv')) return 'FLV';
    if (declared == 'mp4' || url.contains('.mp4')) return 'MP4';
    return 'Auto';
  }

  int _ms(DateTime started) =>
      DateTime.now().difference(started).inMilliseconds;

  String _shortError(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 110 ? text : '${text.substring(0, 107)}...';
  }

  @override
  Widget build(BuildContext context) {
    final okCount =
        _results.where((x) => x.status == _DiagStatus.ok).length;
    final failCount =
        _results.where((x) => x.status == _DiagStatus.fail).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN-Free Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Run again',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    failCount == 0 && okCount > 0
                        ? Icons.verified_rounded
                        : Icons.network_check_rounded,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _running
                              ? 'Testing direct connections…'
                              : (failCount == 0
                                  ? 'Direct connection looks usable'
                                  : 'Some endpoints need attention'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          kIsWeb
                              ? 'Web tests also reflect browser CORS rules.'
                              : 'Tests use the phone network directly. No VPN bypass is performed.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_running) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          ..._results.map((result) => _ResultTile(result: result)),
          const SizedBox(height: 14),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.system_update_alt_rounded),
                title: const Text(
                  'App updates',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: const Text(
                  'NCA can check, download and open the latest APK installer directly.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => AppUpdateService.check(context, force: true),
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            'HLS-first policy',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Healthy HLS (.m3u8) lines are preferred first. If a line fails, '
            'the player can try the next configured line. A network or host '
            'block still requires a directly reachable authorized source.',
          ),
        ],
      ),
    );
  }
}

enum _DiagStatus { ok, warning, fail }

class _DiagResult {
  const _DiagResult({
    required this.title,
    required this.detail,
    required this.status,
  });

  final String title;
  final String detail;
  final _DiagStatus status;
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final _DiagResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final (icon, color) = switch (result.status) {
      _DiagStatus.ok => (Icons.check_circle_rounded, Colors.green),
      _DiagStatus.warning => (Icons.warning_amber_rounded, Colors.orange),
      _DiagStatus.fail => (Icons.cancel_rounded, colors.error),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          result.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(result.detail),
      ),
    );
  }
}
