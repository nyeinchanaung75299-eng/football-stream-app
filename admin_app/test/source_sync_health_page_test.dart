import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/source_sync_health_page.dart';

void main() {
  testWidgets('Admin displays truthful partial and unavailable source health',
      (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SourceSyncHealthPage(loader: (source) async {
        requested.add(source);
        if (source == 'highlights') {
          return {'total': 2, 'unavailable': true};
        }
        return {
          'ok': true,
          'state': {
            'status': source == 'darkbyte' ? 'partial' : 'ok',
            'entry_count': 12,
            'last_checked_at': '2026-11-24T00:00:00Z',
            'unavailable_repositories':
                source == 'darkbyte' ? ['rohmanabdu/lian'] : <String>[],
          },
        };
      }),
    ));
    await tester.pumpAndSettle();
    expect(requested.toSet(),
        {'darkbyte', 'repository', 'repository-imports', 'highlights'});
    expect(find.text('Source Sync Health'), findsOneWidget);
    expect(find.text('Stream Hub'), findsOneWidget);
    expect(find.text('Repository Match / Live 2'), findsOneWidget);
    expect(find.text('Admin HL · DasFootball'), findsOneWidget);
    expect(find.text('PARTIAL'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('rohmanabdu/lian'), findsOneWidget);
    expect(find.textContaining('Existing highlights are not deleted'),
        findsOneWidget);
  });

  testWidgets('failed diagnostics remain unknown and do not fake empty data',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SourceSyncHealthPage(loader: (source) async {
        throw StateError('network is down');
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('UNKNOWN'), findsNWidgets(4));
    expect(find.textContaining('No deletion is inferred'), findsNWidgets(4));
    expect(find.text('Source entries: 0'), findsNothing);
  });
}
