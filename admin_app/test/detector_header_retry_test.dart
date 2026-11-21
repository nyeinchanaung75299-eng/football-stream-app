import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/hls_detection_session.dart';
import 'package:football_admin/services/hls_candidate_verifier.dart';
import 'package:football_admin/services/stream_detector_service.dart';

const line = DetectedStream(
    url: 'https://cdn.example/live.m3u8',
    type: 'hls',
    referer: 'https://guessed.example/');
void main() {
  testWidgets(
      'a corrected public header rechecks a failed playlist and can select it',
      (tester) async {
    var calls = 0;
    final picked = <DetectedStream>[];
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: picked.add,
        verify: (stream) async {
          calls++;
          return HlsCandidateCheck(
              stream.referer == 'https://actual.example/', 'result');
        });
    session.observe(line);
    session.documentFinished(session.generation);
    session.associateMedia([line.url], session.generation);
    await tester.pump();
    expect(session.checks[line.url]?.live, false);
    session.observe(line,
        headers: {'Referer': 'https://actual.example/', 'Cookie': 'ignored'});
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 2);
    expect(picked.single.referer, 'https://actual.example/');
    session.observe(line, headers: {'Referer': 'https://actual.example/'});
    await tester.pump();
    expect(calls, 2);
    session.dispose();
  });
  testWidgets(
      'a late failed check cannot overwrite corrected headers in flight',
      (tester) async {
    final first = Completer<HlsCandidateCheck>();
    var calls = 0;
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: (_) {},
        verify: (stream) {
          calls++;
          return calls == 1
              ? first.future
              : Future.value(const HlsCandidateCheck(true, 'corrected'));
        });
    session.observe(line);
    session.observe(line, headers: {'Referer': 'https://actual.example/'});
    first.complete(const HlsCandidateCheck(false, 'old denied'));
    await tester.pump();
    expect(calls, 2);
    expect(session.checks[line.url]?.live, true);
    session.dispose();
  });
  testWidgets('same-document reset preserves ready state and selection resumes',
      (tester) async {
    final picked = <DetectedStream>[];
    final session = HlsDetectionSession(
        quickSelect: true,
        onChanged: () {},
        onSelected: picked.add,
        verify: (_) async => const HlsCandidateCheck(true, 'live'));
    session.documentFinished(session.generation);
    session.reset(documentLoaded: session.loaded);
    session.observe(line);
    session.associateMedia([line.url], session.generation);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(picked, [line]);
    session.dispose();
  });
}
