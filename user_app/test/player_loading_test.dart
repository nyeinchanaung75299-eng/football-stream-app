import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/player_loading.dart';
import 'package:football_viewer/source_line_loader.dart';

void main() {
  testWidgets(
    'closing a successful spinner keeps pending backup loading active',
    (tester) async {
      final late = Completer<SourceLines>();
      final operation = SourceLineLoader(
        anchors: [
          () async => [
            {'id': 'first', 'stream_url': 'https://example.test/first.m3u8'},
          ],
          () => late.future,
        ],
        compare: (_, __) => 0,
      );
      SourceLines? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    result = await loadPlayerSources<SourceLines?>(context, () {
                      operation.start();
                      return operation.firstUsable;
                    }, onCancelled: operation.cancel);
                  },
                  child: const Text('Watch'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();
      expect(result!.single['id'], 'first');
      expect(operation.cancelled, isFalse);
      expect(operation.loading, isTrue);
      late.complete([
        {'id': 'backup', 'stream_url': 'https://example.test/backup.m3u8'},
      ]);
      await tester.pumpAndSettle();
      expect(operation.rows.length, 2);
      operation.dispose();
    },
  );

  testWidgets(
    'Cancel stops pending anchors without waiting for HTTP completion',
    (tester) async {
      final pending = Completer<SourceLines>();
      final operation = SourceLineLoader(
        anchors: [() => pending.future],
        compare: (_, __) => 0,
      );
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    final result = await loadPlayerSources<SourceLines?>(
                      context,
                      () {
                        operation.start();
                        return operation.firstUsable;
                      },
                      onCancelled: operation.cancel,
                    );
                    expect(result, isNull);
                    completed = true;
                  },
                  child: const Text('Watch'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(operation.cancelled, isTrue);
      expect(pending.isCompleted, isFalse);
      pending.complete([
        {'id': 'late', 'stream_url': 'https://example.test/late.m3u8'},
      ]);
      await tester.pumpAndSettle();
      expect(operation.rows, isEmpty);
      expect(find.text('Watch'), findsOneWidget);
      operation.dispose();
    },
  );

  testWidgets(
    'Back during line loading keeps the source page and cancels the chooser',
    (tester) async {
      final pending = Completer<List<int>>();
      List<int>? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    result = await loadPlayerSources(
                      context,
                      () => pending.future,
                    );
                    completed = true;
                  },
                  child: const Text('Source page'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Source page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Loading lines…'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Source page'), findsOneWidget);
      pending.complete([1]);
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(result, isNull);
      expect(find.text('Source page'), findsOneWidget);
    },
  );

  testWidgets(
    'a line request failure removes the spinner and offers retry guidance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => loadPlayerSources(context, () async {
                    throw StateError('Network failed');
                  }),
                  child: const Text('Watch'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Watch'));
      await tester.pumpAndSettle();
      expect(find.text('Loading lines…'), findsNothing);
      expect(
        find.text('Could not load lines. Check your connection and try again.'),
        findsOneWidget,
      );
    },
  );
}
