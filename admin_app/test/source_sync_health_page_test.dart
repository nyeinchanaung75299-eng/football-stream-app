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
    expect(find.text('PARTIAL'), findsOneWidget);
    expect(find.textContaining('rohmanabdu/lian'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Admin HL · DasFootball'), 200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Admin HL · DasFootball'), findsOneWidget);
    expect(find.text('UNAVAILABLE'), findsOneWidget);
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
    for (final title in [
      'Stream Hub', 'Repository Match / Live 2',
      'Repository Link Updates', 'Admin HL · DasFootball',
    ]) {
      await tester.scrollUntilVisible(find.text(title), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      final card = find.ancestor(of: find.text(title),
          matching: find.byType(Card));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('UNKNOWN')),
          findsOneWidget);
      expect(find.descendant(of: card,
          matching: find.textContaining('No deletion is inferred')),
          findsOneWidget);
      expect(find.descendant(of: card,
          matching: find.text('Source entries: 0')), findsNothing);
    }
  });
}
