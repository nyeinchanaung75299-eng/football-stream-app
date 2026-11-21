import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/line_share_sheet.dart';
import 'package:football_admin/services/line_share_payload.dart';

void main() {
  testWidgets(
      'whole-match preview fits a small phone and does not send on open',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = LineSharePayload(
        'Singapore vs Brazil',
        List.generate(
            30,
            (i) => {
                  'label': 'Line $i',
                  'stream_type': 'hls',
                  'stream_url': 'https://cdn.example/$i.m3u8',
                }));
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showLineShareSheet(context, payload),
                    child: const Text('Preview'))))));
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Share all lines'), findsOneWidget);
    expect(find.text('Share to Telegram'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    expect(find.text('Export .txt'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'].toString();
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.text('Copy all'));
    await tester.pumpAndSettle();
    expect(copied, contains('Singapore vs Brazil'));
    expect(find.text('Copied ✓'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Share all lines'), findsNothing);
  });
}
