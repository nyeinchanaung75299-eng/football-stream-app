import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/stream_detector_page_web.dart';

void main() {
  testWidgets('website scanner is the primary mode and requires consent',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamDetectorPage()));

    expect(find.text('Website Stream Detector'), findsOneWidget);
    expect(find.byKey(const Key('website-scan-url')), findsOneWidget);
    expect(find.byKey(const Key('scan-website')), findsOneWidget);
    final button = tester.widget<FilledButton>(
        find.byKey(const Key('scan-website')));
    expect(button.onPressed, isNull);
    expect(find.byKey(const Key('website-scan-mode')), findsOneWidget);
    expect(find.textContaining('Enter a website watch-page'), findsOneWidget);
  });

  testWidgets('website scanner rejects an invalid URL before network access',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamDetectorPage()));
    await tester.enterText(
      find.byKey(const Key('website-scan-url')), 'not a URL',
    );
    await tester.tap(find.byKey(const Key('scan-authorized')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-website')));
    await tester.pump();
    expect(find.text('Enter a full http(s) website URL.'), findsOneWidget);
  });

  testWidgets('manual fallback accepts authorized direct HLS URL',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamDetectorPage()));
    await tester.ensureVisible(find.byKey(const Key('manual-mode-expander')));
    await tester.tap(find.byKey(const Key('manual-mode-expander')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('web-stream-url')));
    await tester.enterText(
      find.byKey(const Key('web-stream-url')),
      'https://cdn.example.org/live/master.m3u8',
    );
    await tester.ensureVisible(find.byKey(const Key('web-check-stream')));
    await tester.tap(find.byKey(const Key('web-check-stream')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ready for testing'), 170,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ready for testing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Add to Servers'), 100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add to Servers'), findsOneWidget);
  });

  testWidgets('manual fallback rejects a website watch page',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamDetectorPage()));
    await tester.ensureVisible(find.byKey(const Key('manual-mode-expander')));
    await tester.tap(find.byKey(const Key('manual-mode-expander')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('web-stream-url')));
    await tester.enterText(
      find.byKey(const Key('web-stream-url')),
      'https://example.org/watch',
    );
    await tester.ensureVisible(find.byKey(const Key('web-check-stream')));
    await tester.tap(find.byKey(const Key('web-check-stream')));
    await tester.pump();
    expect(find.textContaining('Enter a direct M3U8'), findsOneWidget);
    expect(find.text('Add to Servers'), findsNothing);
  });
}
