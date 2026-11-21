import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/unsaved_changes_guard.dart';

void main() {
  testWidgets('Back keeps an unsaved editor until Discard is explicitly chosen',
      (tester) async {
    final field = TextEditingController();
    addTearDown(field.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => UnsavedChangesGuard(
                                controllers: [field],
                                child: Scaffold(
                                    appBar: AppBar(title: const Text('Editor')),
                                    body: TextField(controller: field))))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(field.text, 'unsaved');
    expect(find.text('Editor'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Editor'), findsNothing);
  });
  testWidgets('a scalar-only edit also asks before closing', (tester) async {
    var changed = false;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => StatefulBuilder(
                                builder: (ctx, set) => UnsavedChangesGuard(
                                    controllers: const [],
                                    dirty: () => changed,
                                    child: Scaffold(
                                        appBar:
                                            AppBar(title: const Text('Editor')),
                                        body: Switch(
                                            value: changed,
                                            onChanged: (value) => set(
                                                () => changed = value))))))),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
  });
}
