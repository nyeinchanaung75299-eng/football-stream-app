import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_viewer/widgets/player_server_rail.dart';

void main() {
  const sources = <Map<String, dynamic>>[
    {
      'label': 'Primary HD',
      'url': 'https://secret.example.invalid/live.m3u8?token=hidden',
      'referer': 'https://private.example.invalid/',
      'keyData': 'not-for-the-ui',
    },
    {'label': 'Backup line with a deliberately long display name'},
    {'resolution': '720p'},
  ];

  Widget app({
    required int selectedIndex,
    required ValueChanged<int> onSelected,
    Set<int> failed = const <int>{},
    int? loading,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true)
          .copyWith(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PlayerServerRail(
            sources: sources,
            selectedIndex: selectedIndex,
            failedIndices: failed,
            loadingIndex: loading,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }

  testWidgets('shows a horizontal selected line without credential metadata', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(280, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app(selectedIndex: 0, onSelected: (_) {}));

    expect(find.byKey(const ValueKey('player-server-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-line-check-0')), findsOneWidget);
    expect(find.text('Primary HD'), findsOneWidget);
    expect(find.textContaining('token=hidden'), findsNothing);
    expect(find.textContaining('not-for-the-ui'), findsNothing);
    expect(find.textContaining('private.example'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches only when a different line is tapped', (tester) async {
    int? picked;
    await tester.pumpWidget(
      app(selectedIndex: 0, onSelected: (index) => picked = index),
    );

    await tester.tap(find.byKey(const ValueKey('player-line-chip-0')));
    await tester.pump();
    expect(picked, isNull);

    await tester.tap(find.byKey(const ValueKey('player-line-chip-1')));
    await tester.pump();
    expect(picked, 1);
  });

  testWidgets('marks failed and loading lines without losing selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(selectedIndex: 1, failed: const {0}, loading: 1, onSelected: (_) {}),
    );

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('player-line-check-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('player-line-loading-1')), findsOneWidget);
  });

  testWidgets('replaces a credential-shaped label with a safe line number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerServerRail(
          sources: const [
            {
              'label': 'https://private.invalid/live?token=SECRET',
              'url': 'https://private.invalid/live.m3u8?token=SECRET',
            },
          ],
          selectedIndex: 0,
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('Line 1'), findsOneWidget);
    expect(find.textContaining('private.invalid'), findsNothing);
    expect(find.textContaining('SECRET'), findsNothing);
  });
}
