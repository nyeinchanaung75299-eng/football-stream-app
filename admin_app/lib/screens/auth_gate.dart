import 'dart:async';

import 'package:flutter/material.dart';

import '../analytics_service.dart';
import '../services/admin_auth_service.dart';
import 'dashboard_page.dart';
import 'login_page.dart';

enum _AdminAccess { signedOut, checking, allowed, failed, denied }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.auth});

  final AdminAuthService? auth;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AdminAuthService _auth;
  late final StreamSubscription<AdminAuthChange> _subscription;
  _AdminAccess _access = _AdminAccess.signedOut;
  int _validationEpoch = 0;
  bool _signingOut = false;
  String? _accessMessage;
  String? _errorMessage;
  String? _verifiedUserId;
  GlobalKey<NavigatorState> _adminNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? SupabaseAdminAuthService();
    _subscription = _auth.userChanges.listen(
      (change) => _sessionChanged(
        change.userId,
        preserveAccess: change.isTokenRefresh,
      ),
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        _validationEpoch += 1;
        _dismissRootOverlays();
        setState(() {
          _verifiedUserId = null;
          _access = _AdminAccess.failed;
          _errorMessage =
              'Could not verify your session. Check your connection and retry.';
        });
      },
    );
    _sessionChanged(_auth.currentUserId);
  }

  @override
  void dispose() {
    _validationEpoch += 1;
    unawaited(_subscription.cancel());
    super.dispose();
  }

  void _sessionChanged(String? userId, {bool preserveAccess = false}) {
    if (!mounted) return;
    final epoch = ++_validationEpoch;
    if (userId == null) {
      _dismissRootOverlays();
      setState(() {
        _verifiedUserId = null;
        _access = _AdminAccess.signedOut;
        _errorMessage = null;
      });
      return;
    }
    // Auth refresh events can arrive while a rejected account is signing out.
    if (_signingOut) return;
    final keepVerifiedAccess = preserveAccess &&
        _access == _AdminAccess.allowed &&
        _verifiedUserId == userId;
    if (!keepVerifiedAccess) _dismissRootOverlays();
    setState(() {
      if (!keepVerifiedAccess) {
        _verifiedUserId = null;
        _access = _AdminAccess.checking;
      }
      _accessMessage = null;
      _errorMessage = null;
    });
    unawaited(_validateAdmin(userId, epoch));
  }

  void _dismissRootOverlays() {
    if (_verifiedUserId == null) return;
    // showDialog uses the root Navigator by default, outside the protected
    // Navigator below. Close those dialogs when their verified access is lost.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    });
  }

  bool _isCurrentValidation(String userId, int epoch) =>
      mounted &&
      epoch == _validationEpoch &&
      _auth.currentUserId == userId;

  Future<void> _validateAdmin(String userId, int epoch) async {
    try {
      final allowed = await _auth.isAdmin(userId);
      if (!_isCurrentValidation(userId, epoch)) return;
      if (allowed) {
        final firstVerification = _verifiedUserId != userId;
        setState(() {
          if (firstVerification) {
            _adminNavigatorKey = GlobalKey<NavigatorState>();
          }
          _verifiedUserId = userId;
          _access = _AdminAccess.allowed;
        });
        if (firstVerification) {
          unawaited(AnalyticsService.capture('admin login succeeded'));
        }
        return;
      }
      _dismissRootOverlays();
      setState(() {
        _verifiedUserId = null;
        _access = _AdminAccess.denied;
        _accessMessage = 'This account does not have admin access.';
      });
      await _signOut();
    } catch (_) {
      if (!_isCurrentValidation(userId, epoch)) return;
      _dismissRootOverlays();
      setState(() {
        _verifiedUserId = null;
        _access = _AdminAccess.failed;
        _errorMessage =
            'Could not verify admin access. Check your connection and retry.';
      });
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    _validationEpoch += 1;
    setState(() => _signingOut = true);
    try {
      await _auth.signOut();
      if (mounted && _auth.currentUserId == null) _sessionChanged(null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifiedUserId = null;
        if (_access != _AdminAccess.denied) _access = _AdminAccess.failed;
        _errorMessage =
            'Could not sign out. Check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
        if (_access == _AdminAccess.signedOut && _auth.currentUserId != null) {
          _sessionChanged(_auth.currentUserId);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_access == _AdminAccess.signedOut) {
      return LoginPage(auth: _auth, accessMessage: _accessMessage);
    }
    if (_access == _AdminAccess.allowed) {
      // All protected routes belong to this verified session. Removing this
      // Navigator also removes any editor that was open when access was lost.
      return NavigatorPopHandler<void>(
        onPopWithResult: (_) => _adminNavigatorKey.currentState?.pop(),
        child: HeroControllerScope.none(
          child: Navigator(
            key: _adminNavigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/admin/dashboard'),
              builder: (_) => const DashboardPage(),
            ),
          ),
        ),
      );
    }

    final checking = _access == _AdminAccess.checking;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (checking) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Checking admin access…'),
                ] else ...[
                  const Icon(Icons.lock_outline_rounded, size: 44),
                  const SizedBox(height: 16),
                  Text(
                    _access == _AdminAccess.denied
                        ? 'Admin access required'
                        : 'Unable to verify admin access',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? _accessMessage ?? '',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  if (_access == _AdminAccess.failed)
                    FilledButton(
                      onPressed: _signingOut
                          ? null
                          : () => _sessionChanged(_auth.currentUserId),
                      child: const Text('RETRY'),
                    ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _signingOut ? null : _signOut,
                  child: Text(_signingOut ? 'SIGNING OUT…' : 'SIGN OUT'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
