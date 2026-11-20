import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'stream_detector_service.dart';

class HlsCandidateCheck {
  const HlsCandidateCheck(this.live, this.note, {this.httpStatus});
  final bool live;
  final String note;
  final int? httpStatus;
}

/// Bounded playlist-only validation. Never read WebView cookies, Authorization,
/// DRM keys or media segments. A successful playlist is not decoded video proof.
class HlsCandidateVerifier {
  HlsCandidateVerifier(
      {http.Client Function()? clientFactory,
      this.timeout = const Duration(seconds: 6)})
      : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Duration timeout;
  final Set<http.Client> _active = {};
  static const maxBytes = 65536;

  static bool publicUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.contains(':') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) return false;
    return true;
  }

  static bool adCandidate(Uri uri) => RegExp(
          r'(^|[./_-])(ads?|preroll|vast|vmap|doubleclick|googlesyndication)([./_-]|$)',
          caseSensitive: false)
      .hasMatch('${uri.host}${uri.path}');

  Future<HlsCandidateCheck> verify(DetectedStream stream) async {
    final uri = Uri.tryParse(stream.url);
    if (uri == null || !publicUri(uri) || adCandidate(uri)) {
      return const HlsCandidateCheck(false, 'Manual selection required');
    }
    final client = _clientFactory();
    _active.add(client);
    try {
      return await _playlist(client, uri, stream, 0).timeout(timeout);
    } catch (_) {
      return const HlsCandidateCheck(false, 'Playlist could not be verified');
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  Future<HlsCandidateCheck> _playlist(
      http.Client client, Uri uri, DetectedStream stream, int depth,
      {int redirects = 0}) async {
    if (!publicUri(uri) || adCandidate(uri))
      return const HlsCandidateCheck(false, 'Manual selection required');
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers.addAll({
      'Accept':
          'application/vnd.apple.mpegurl, application/x-mpegURL, text/plain',
      'Range': 'bytes=0-${maxBytes - 1}',
      if (stream.referer.isNotEmpty) 'Referer': stream.referer,
      if (stream.origin.isNotEmpty) 'Origin': stream.origin,
    });
    final response = await client.send(request);
    if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
      final location = response.headers['location'];
      await response.stream.take(0).drain<void>();
      if (location == null || redirects >= 2)
        return const HlsCandidateCheck(
            false, 'Playlist redirect could not be verified');
      return _playlist(client, uri.resolve(location), stream, depth,
          redirects: redirects + 1);
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      await response.stream.take(0).drain<void>();
      return HlsCandidateCheck(
          false, 'HTTP ${response.statusCode} — not verified',
          httpStatus: response.statusCode);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxBytes)
        return const HlsCandidateCheck(
            false, 'Playlist exceeds quick-check size');
      bytes.addAll(chunk);
    }
    final range = response.headers['content-range'];
    if (response.statusCode == 206 &&
        (range == null || int.tryParse(range.split('/').last) != bytes.length)) {
      return const HlsCandidateCheck(false, 'Partial playlist — choose manually');
    }
    final body = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .trim();
    if (!body.startsWith('#EXTM3U'))
      return const HlsCandidateCheck(false, 'Response is not an HLS playlist');
    if (body.contains('#EXT-X-ENDLIST') ||
        RegExp(r'#EXT-X-PLAYLIST-TYPE:\s*VOD').hasMatch(body)) {
      return const HlsCandidateCheck(false, 'Finite video — choose manually');
    }
    if (body.contains('#EXT-X-STREAM-INF:')) {
      if (depth >= 2)
        return const HlsCandidateCheck(false, 'Choose the playlist manually');
      final lines = const LineSplitter().convert(body);
      for (var i = 0; i + 1 < lines.length; i++) {
        if (!lines[i].startsWith('#EXT-X-STREAM-INF:')) continue;
        final child = lines.skip(i + 1).map((v) => v.trim()).firstWhere(
            (v) => v.isNotEmpty && !v.startsWith('#'),
            orElse: () => '');
        if (child.isNotEmpty)
          return _playlist(client, uri.resolve(child), stream, depth + 1);
      }
    }
    final live =
        body.contains('#EXTINF:') && body.contains('#EXT-X-TARGETDURATION:');
    return HlsCandidateCheck(
        live,
        live
            ? 'Live playlist verified; video not tested'
            : 'HLS media playlist not confirmed',
        httpStatus: response.statusCode);
  }

  void cancel() {
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }
}
