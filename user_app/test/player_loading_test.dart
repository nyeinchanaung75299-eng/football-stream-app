import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/player_loading.dart';

void main() {
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
