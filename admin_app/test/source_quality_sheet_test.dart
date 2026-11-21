import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/source_quality_sheet.dart';

void main() {
  final lines = [
    for (var i = 0; i < 2; i++)
      {
        'label': 'HD source $i',
        'stream_type': 'hls',
        'url': 'https://cdn.example/$i/live.m3u8',
        'referer': 'https://publisher.example/'
      }
  ];
  for (final scale in [1.0, 2.0])
    testWidgets('source quality supports phone width and text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: const Size(360, 800),
                  textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                  body: SourceQualitySheet(
                      title: 'A long home team vs A long away team',
                      lines: lines,
                      onAdd: (_) async => null,
                      onRefresh: () {},
                      onTest: (_) async {},
                      onOpenMatch: (_) {})))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  testWidgets(
      'batch failure retains selection, blocks double tap and successful retry stays open',
      (tester) async {
    final gate = Completer<Map<String, dynamic>?>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SourceQualitySheet(
                title: 'Home vs Away',
                lines: lines,
                onAdd: (selected) {
                  calls++;
                  expect(selected.length, 2);
                  return calls == 1
                      ? gate.future
                      : Future.value({'match_id': 'saved'});
                },
                onRefresh: () {},
                onTest: (_) async {},
                onOpenMatch: (_) {}))));
    await tester.tap(find.text('Select all'));
    await tester.pump();
    await tester.ensureVisible(find.text('ADD SELECTED (2)'));
    await tester.tap(find.text('ADD SELECTED (2)'));
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'ADD SELECTED (2)'))
            .onPressed,
        isNull);
    expect(calls, 1);
    gate.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('ADD SELECTED (2)'), findsOneWidget);
    await tester.tap(find.text('ADD SELECTED (2)'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Select Stream Quality'), findsOneWidget);
    expect(find.text('ADDED ✓'), findsNWidgets(2));
    expect(find.text('Open match in Controls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
