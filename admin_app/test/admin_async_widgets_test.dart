import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/source_destination_picker.dart';
import 'package:football_admin/widgets/stream_links_list.dart';

void main() {
  testWidgets('Match switch hides old row actions until replacement data arrives', (tester) async {
    final oldFuture = Future.value(<Map<String, dynamic>>[
      {'id': 'old-server'},
    ]);
    final pending = Completer<List<Map<String, dynamic>>>();
    Widget screen(Future<List<Map<String, dynamic>>> future) => MaterialApp(
          home: Scaffold(
            body: StreamLinksList(
              future: future,
              rowBuilder: (row) => TextButton(
                onPressed: () {},
                child: Text('Delete ${row['id']}'),
              ),
            ),
          ),
        );

    await tester.pumpWidget(screen(oldFuture));
    await tester.pump();
    expect(find.text('Delete old-server'), findsOneWidget);

    // Keep the same widget key to exercise FutureBuilder's retained old data.
    await tester.pumpWidget(screen(pending.future));
    expect(find.text('Delete old-server'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete([{'id': 'new-server'}]);
    await tester.pump();
    expect(find.text('Delete old-server'), findsNothing);
    expect(find.text('Delete new-server'), findsOneWidget);
  });

  testWidgets('Failed replacement query does not revive previous server actions', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    Widget screen(Future<List<Map<String, dynamic>>> future) => MaterialApp(
          home: Scaffold(
            body: StreamLinksList(
              future: future,
              rowBuilder: (row) => Text('Edit ${row['id']}'),
            ),
          ),
        );

    await tester.pumpWidget(screen(Future.value([{'id': 'old-server'}])));
    await tester.pump();
    expect(find.text('Edit old-server'), findsOneWidget);
    await tester.pumpWidget(screen(pending.future));
    pending.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text('Edit old-server'), findsNothing);
    expect(find.text('Could not load servers. Tap refresh to try again.'), findsOneWidget);
  });

  testWidgets('Destination loading preserves the published match preset', (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    var changes = 0;
    final screen = MaterialApp(
      home: Scaffold(
        body: SourceDestinationPicker(
          future: pending.future,
          selectedId: 'published-match',
          onChanged: (_) => changes++,
        ),
      ),
    );

    await tester.pumpWidget(screen);
    var dropdown = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.value, isNull);
    expect(dropdown.onChanged, isNull);
    expect(changes, 0);

    pending.complete([
      {'id': 'other-match', 'home_team': 'A', 'away_team': 'B'},
      {'id': 'published-match', 'home_team': 'C', 'away_team': 'D'},
    ]);
    await tester.pump();
    dropdown = tester.widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dropdown.value, 'published-match');
    expect(dropdown.onChanged, isNotNull);
    expect(changes, 0);
  });
}
