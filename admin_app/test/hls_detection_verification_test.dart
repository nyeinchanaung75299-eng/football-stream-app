import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_admin/services/hls_candidate_verifier.dart';
import 'package:football_admin/services/hls_detection_session.dart';
import 'package:football_admin/services/stream_detector_service.dart';

const live =
    '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:12\n#EXTINF:6,\nseg.ts\n';
const one = DetectedStream(
    url: 'https://cdn.example/live.m3u8',
    type: 'hls',
    referer: 'https://playerbee.top/',
    origin: 'https://playerbee.top');
void main() {
  test(
      'only public 2xx complete live playlists qualify; no credentials or segments fetched',
      () async {
    final requests = <http.Request>[];
    final verifier = HlsCandidateVerifier(
        clientFactory: () => MockClient((r) async {
              requests.add(r);
              return http.Response(live, 200);
            }));
    final check = await verifier.verify(one);
    expect(check.live, true);
    expect(requests.length, 1);
    expect(
        requests.single.headers.keys
            .any((k) => ['cookie', 'authorization'].contains(k.toLowerCase())),
        false);
    expect(requests.single.headers['Referer'], 'https://playerbee.top/');
    expect(requests.single.url.path, '/live.m3u8');
    verifier.cancel();
  });
  test(
      '403, HTML, VOD, ad URLs, private hosts and incomplete ranges never auto qualify',
      () async {
    for (final response in [
      http.Response('denied', 403),
      http.Response('<html/>', 200),
      http.Response('$live#EXT-X-ENDLIST\n', 200),
      http.Response(live, 206, headers: {'content-range': 'bytes 0-60/5000'})
    ]) {
      final v = HlsCandidateVerifier(
          clientFactory: () => MockClient((_) async => response));
      expect((await v.verify(one)).live, false);
    }
    var calls = 0;
    final v = HlsCandidateVerifier(
        clientFactory: () => MockClient((_) async {
              calls++;
              return http.Response(live, 200);
            }));
    for (final url in [
      'https://127.0.0.1/private.m3u8',
      'https://cdn.example/ads/preroll.m3u8',
      'https://localhost/a.m3u8'
    ]) {
      expect(
          (await v.verify(DetectedStream(url: url, type: 'hls'))).live, false);
    }
    expect(calls, 0);
  });
  test(
      'master playlist validates a public live variant but never downloads media',
      () async {
    final paths = <String>[];
    final v = HlsCandidateVerifier(
        clientFactory: () => MockClient((r) async {
              paths.add(r.url.path);
              return http.Response(
                  r.url.path == '/live.m3u8'
                      ? '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=900000\nlow.m3u8\n'
                      : live,
                  200);
            }));
    expect((await v.verify(one)).live, true);
    expect(paths, ['/live.m3u8', '/low.m3u8']);
  });
  testWidgets(
      'quick selection waits for validation, document completion and quiet period',
      (tester) async {
    final selected = <DetectedStream>[];
    final pending = Completer<HlsCandidateCheck>();
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: selected.add,
        verify: (_) => pending.future);
    session.observe(one);
    await tester.pump(const Duration(seconds: 4));
    expect(selected, isEmpty);
    pending.complete(const HlsCandidateCheck(true, 'verified'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(selected, isEmpty);
    session.associateMedia([one.url], session.generation);
    session.documentFinished(session.generation);
    await tester.pump(const Duration(seconds: 2));
    expect(selected, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(selected, [one]);
    session.dispose();
  });
  test(
      'later resource metadata cannot replace actual Referer with a page guess',
      () {
    final session = HlsDetectionSession(
        quickSelect: false, onChanged: () {}, onSelected: (_) {});
    session.observe(one);
    session.observe(
        const DetectedStream(
            url: 'https://cdn.example/live.m3u8',
            type: 'hls',
            referer: 'https://wrong.example/page'),
        headers: {});
    expect(session.streams.single.referer, one.referer);
    session.observe(one, headers: {
      'Referer': 'https://playerbee.top/actual',
      'Cookie': 'private'
    });
    expect(session.streams.single.referer, 'https://playerbee.top/actual');
    session.dispose();
  });
  testWidgets(
      'a lone unrelated HLS request cannot auto-select as the match video',
      (tester) async {
    final picked = <DetectedStream>[];
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: picked.add,
        verify: (_) async => const HlsCandidateCheck(true, 'live playlist'));
    session.observe(one);
    session.documentFinished(session.generation);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(picked, isEmpty);
    session.dispose();
  });
  testWidgets(
      'late second playlist, failed verification and old navigation cannot auto-select',
      (tester) async {
    final selected = <DetectedStream>[];
    final pending = Completer<HlsCandidateCheck>();
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: selected.add,
        verify: (_) => pending.future);
    session.observe(one);
    session.documentFinished(session.generation);
    session.reset();
    pending.complete(const HlsCandidateCheck(true, 'old page'));
    await tester.pump(const Duration(seconds: 5));
    expect(session.streams, isEmpty);
    expect(selected, isEmpty);
    session.dispose();
    final ambiguous = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: selected.add,
        verify: (_) async => const HlsCandidateCheck(true, 'verified'));
    ambiguous.observe(one);
    ambiguous.documentFinished(ambiguous.generation);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    ambiguous.observe(const DetectedStream(
        url: 'https://cdn.example/other.m3u8', type: 'hls'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(selected, isEmpty);
    ambiguous.dispose();
    final denied = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: selected.add,
        verify: (_) async => const HlsCandidateCheck(false, 'HTTP 403'));
    denied.observe(one);
    denied.documentFinished(denied.generation);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(selected, isEmpty);
    denied.dispose();
  });
}
