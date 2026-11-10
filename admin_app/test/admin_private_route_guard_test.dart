import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/services/admin_private_route_guard.dart';

void main() {
  testWidgets('session termination closes stacked private pages and dialogs',
      (tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        rootContext = context;
        return const Scaffold(body: Center(child: Text('Login')));
      }),
    ));

    Navigator.of(rootContext).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(
        child: Text('Private Soco Account A FC'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Private Soco Account A FC'), findsOneWidget);

    showDialog<void>(
      context: rootContext,
      builder: (_) => const AlertDialog(title: Text('Private source details')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private source details'), findsOneWidget);

    // This is the same operation used by the AuthGate auth-state listener.
    closeAdminPrivateRoutes(rootContext);
    await tester.pumpAndSettle();
    expect(find.text('Private source details'), findsNothing);
    expect(find.text('Private Soco Account A FC'), findsNothing);
    expect(find.text('Login'), findsOneWidget);
  });
}
