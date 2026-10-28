import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:football_viewer/screens/channels_page.dart';

void main() {
  testWidgets('four channels wrap into two rows at phone and desktop widths', (
    tester,
  ) async {
    for (final width in [390.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(key: ValueKey(width), home: const ChannelsPage()),
          );
          await tester.pumpAndSettle();
          final a = tester.getRect(find.text('Channel 1'));
          final b = tester.getRect(find.text('Channel 2'));
          final c = tester.getRect(find.text('Channel 3'));
          final d = tester.getRect(find.text('Channel 4'));
          expect(a.top, b.top);
          expect(c.top, d.top);
          expect(c.top, greaterThan(a.top));
          expect(b.left, greaterThan(a.left));
          expect(c.left, a.left);
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'ok': true,
              'channels': List.generate(
                4,
                (i) => {
                  'id': 'id-$i',
                  'name': 'Channel ${i + 1}',
                  'category': 'Sport',
                },
              ),
            }),
            200,
          ),
        ),
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
