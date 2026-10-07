import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_admin/screens/auth_gate.dart';
import 'package:football_admin/services/admin_auth_service.dart';

class _RoleLookup {
  _RoleLookup(this.userId);

  final String userId;
  final result = Completer<bool>();
}

class _FakeAuth implements AdminAuthService {
  _FakeAuth({this.currentUserId});

  final changes = StreamController<AdminAuthChange>.broadcast(sync: true);
  final lookups = <_RoleLookup>[];
  int signOutCalls = 0;
  int signInCalls = 0;
  Object? signOutError;
  Object? signInError;
  String? submittedEmail;
  String? submittedPassword;

  @override
  String? currentUserId;

  @override
  Stream<AdminAuthChange> get userChanges => changes.stream;

  void changeUser(String? userId, {bool tokenRefresh = false}) {
    currentUserId = userId;
    changes.add(AdminAuthChange(userId, isTokenRefresh: tokenRefresh));
  }

  @override
  Future<bool> isAdmin(String userId) {
    final lookup = _RoleLookup(userId);
    lookups.add(lookup);
    return lookup.result.future;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    signInCalls += 1;
    submittedEmail = email;
    submittedPassword = password;
    if (signInError != null) throw signInError!;
    changeUser('signed-in-user');
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    if (signOutError != null) throw signOutError!;
    changeUser(null);
  }
}

Future<void> _mount(WidgetTester tester, _FakeAuth auth) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.changes.close();
  });
  await tester.pumpWidget(MaterialApp(home: AuthGate(auth: auth)));
}

void main() {
  testWidgets('restored sessions wait for an admin role before Dashboard',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'restored-user');
    await _mount(tester, auth);

    expect(auth.lookups.single.userId, 'restored-user');
    expect(find.text('Checking admin access…'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);

    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsOneWidget);
  });

  testWidgets('credential sign-in stays blocked until its role is confirmed',
      (tester) async {
    final auth = _FakeAuth();
    await _mount(tester, auth);

    await tester.enterText(find.byType(TextField).first, ' admin@example.com ');
    await tester.enterText(find.byType(TextField).last, 'password');
    await tester.tap(find.text('SIGN IN'));
    await tester.pump();

    expect(auth.signInCalls, 1);
    expect(auth.submittedEmail, 'admin@example.com');
    expect(auth.submittedPassword, 'password');
    expect(auth.lookups.single.userId, 'signed-in-user');
    expect(find.text('Checking admin access…'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);

    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsOneWidget);
  });

  testWidgets('non-admin restored session is signed out with a clear reason',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'viewer');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(false);
    await tester.pumpAndSettle();

    expect(auth.signOutCalls, 1);
    expect(auth.currentUserId, isNull);
    expect(find.text('NCA Admin'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('This account does not have admin access.'), findsOneWidget);
  });

  testWidgets('role lookup failure stays blocked and retry verifies again',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.completeError(Exception('network unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('NCA Admin'), findsNothing);
    expect(find.text('Unable to verify admin access'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('SIGN OUT'), findsOneWidget);
    expect(auth.signOutCalls, 0);

    await tester.tap(find.text('RETRY'));
    await tester.pump();
    expect(auth.lookups, hasLength(2));
    expect(find.text('NCA Admin'), findsNothing);
    auth.lookups.last.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsOneWidget);
  });

  testWidgets('lookup failure also lets the user sign out', (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.completeError(Exception('request failed'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SIGN OUT'));
    await tester.pumpAndSettle();
    expect(auth.currentUserId, isNull);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);
  });

  testWidgets('a late successful lookup cannot restore a signed-out session',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.changeUser(null);
    await tester.pumpAndSettle();

    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);
  });

  testWidgets('a previous user role cannot authorize a different session',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'old-admin');
    await _mount(tester, auth);
    auth.changeUser('new-viewer');
    await tester.pump();

    auth.lookups.first.result.complete(true);
    await tester.pump();
    expect(find.text('NCA Admin'), findsNothing);
    expect(find.text('Checking admin access…'), findsOneWidget);
    auth.lookups.last.result.complete(false);
    await tester.pumpAndSettle();
    expect(auth.currentUserId, isNull);
    expect(find.text('NCA Admin'), findsNothing);
  });

  testWidgets('an auth stream error blocks an already verified admin',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsOneWidget);

    auth.changes.addError(Exception('token refresh failed'));
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsNothing);
    expect(find.text('RETRY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-out removes the protected editor route stack',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Protected editor')),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('Protected editor'), findsOneWidget);

    auth.changeUser(null);
    await tester.pumpAndSettle();
    expect(find.text('Protected editor'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('system back still pops an admin editor', (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Protected editor')),
          ),
        );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Protected editor'), findsNothing);
    expect(find.text('NCA Admin'), findsOneWidget);
  });

  testWidgets('sign-out also dismisses dialogs on the root Navigator',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
      context: tester.element(find.text('NCA Admin')),
      builder: (_) => const AlertDialog(content: Text('Protected dialog')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Protected dialog'), findsOneWidget);

    auth.changeUser(null);
    await tester.pumpAndSettle();
    expect(find.text('Protected dialog'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('same-user token refresh preserves an editor and its input',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: TextField()),
          ),
        );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved match edits');

    auth.changeUser('admin', tokenRefresh: true);
    await tester.pump();
    expect(auth.lookups, hasLength(2));
    expect(find.text('unsaved match edits'), findsOneWidget);
    auth.lookups.last.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('unsaved match edits'), findsOneWidget);
  });

  testWidgets('revoked role on refresh removes the protected editor',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Protected editor')),
          ),
        );
    await tester.pumpAndSettle();

    auth.changeUser('admin', tokenRefresh: true);
    await tester.pump();
    expect(find.text('Protected editor'), findsOneWidget);
    auth.lookups.last.result.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Protected editor'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('failed refresh role check removes the protected editor',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(true);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).last).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Protected editor')),
          ),
        );
    await tester.pumpAndSettle();

    auth.changeUser('admin', tokenRefresh: true);
    await tester.pump();
    auth.lookups.last.result.completeError(Exception('role query failed'));
    await tester.pumpAndSettle();
    expect(find.text('Protected editor'), findsNothing);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('SIGN OUT'), findsOneWidget);
  });

  testWidgets('a rejected account stays blocked if sign-out fails',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'viewer')
      ..signOutError = Exception('network unavailable');
    await _mount(tester, auth);
    auth.lookups.single.result.complete(false);
    await tester.pumpAndSettle();

    expect(find.text('Admin access required'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);
    expect(auth.currentUserId, 'viewer');
    expect(find.text('SIGN OUT'), findsOneWidget);
    auth.signOutError = null;
    await tester.tap(find.text('SIGN OUT'));
    await tester.pumpAndSettle();
    expect(auth.currentUserId, isNull);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('failed sign-out during verification remains recoverable',
      (tester) async {
    final auth = _FakeAuth(currentUserId: 'admin')
      ..signOutError = Exception('network unavailable');
    await _mount(tester, auth);
    await tester.tap(find.text('SIGN OUT'));
    await tester.pumpAndSettle();

    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('NCA Admin'), findsNothing);
    auth.lookups.first.result.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('NCA Admin'), findsNothing);
  });

  testWidgets('invalid credentials retain the login form and helpful error',
      (tester) async {
    final auth = _FakeAuth()..signInError = Exception('invalid credentials');
    await _mount(tester, auth);
    await tester.enterText(find.byType(TextField).first, 'admin@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong-password');
    await tester.tap(find.text('SIGN IN'));
    await tester.pumpAndSettle();

    expect(find.text('Login failed. Check your email and password.'),
        findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(auth.lookups, isEmpty);
    expect(find.text('NCA Admin'), findsNothing);
  });
}
