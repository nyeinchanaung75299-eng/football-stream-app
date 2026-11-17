import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/widgets/admin_version_dialog.dart';

void main() {
  testWidgets('App Version shows runtime version and installed build', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminVersionDialog(
        version: '2.5.21',
        buildNumber: '42789',
      )),
    ));
    expect(find.text('NCA Admin · App Version'), findsOneWidget);
    expect(find.text('Installed version: 2.5.21'), findsOneWidget);
    expect(find.text('Build number: 42789'), findsOneWidget);
    expect(find.textContaining('separate from Viewer'), findsOneWidget);
  });

  testWidgets('Web version is labeled explicitly', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AdminVersionDialog(
        version: '2.5.21', buildNumber: '25', isWeb: true,
      )),
    ));
    expect(find.text('Web version: 2.5.21'), findsOneWidget);
  });
}
