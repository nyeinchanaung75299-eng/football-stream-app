import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dashboard_page.dart';
import '../services/admin_web_source_cache.dart';
import '../services/tv_schedule_service.dart';
import 'login_page.dart';

enum _AdminAccess { allowed, denied, failed }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _checkedUserId;
  String? _cacheBoundUser;
  Future<_AdminAccess>? _accessFuture;

  // Account switch, explicit logout and expired sessions always drop the
  // private in-memory provider cache and shared guide, including in-flight
  // results that might otherwise leak into another Admin's tab.
  void _bindWebCache(String? userId) {
    if (!kIsWeb || _cacheBoundUser == userId) return;
    _cacheBoundUser = userId;
    AdminWebSourceCache.bindUser(userId);
    TvScheduleService.invalidateShared();
  }

  Future<_AdminAccess> _checkAccess(String userId) async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      return profile?['role'] == 'admin'
          ? _AdminAccess.allowed
          : _AdminAccess.denied;
    } catch (_) {
      // A temporary network/profile error must never bypass the Admin gate.
      return _AdminAccess.failed;
    }
  }

  void _ensureCheck(String userId) {
    if (_checkedUserId == userId && _accessFuture != null) return;
    _checkedUserId = userId;
    _accessFuture = _checkAccess(userId);
  }

  void _retry(String userId) {
    setState(() {
      _checkedUserId = userId;
      _accessFuture = _checkAccess(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          _bindWebCache(null);
          _checkedUserId = null;
          _accessFuture = null;
          return const LoginPage();
        }

        final userId = session.user.id;
        _bindWebCache(userId);
        _ensureCheck(userId);

        return FutureBuilder<_AdminAccess>(
          future: _accessFuture,
          builder: (context, accessSnapshot) {
            if (accessSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (accessSnapshot.data == _AdminAccess.allowed) {
              return DashboardPage(key: ValueKey('admin-session-$userId'));
            }

            final lookupFailed =
                accessSnapshot.data == _AdminAccess.failed ||
                accessSnapshot.hasError;
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, size: 48),
                      const SizedBox(height: 14),
                      Text(
                        lookupFailed
                            ? 'Could not verify Admin access.'
                            : 'This account does not have Admin access.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 14),
                      if (lookupFailed)
                        FilledButton.icon(
                          onPressed: () => _retry(userId),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('RETRY'),
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            Supabase.instance.client.auth.signOut(),
                        child: const Text('SIGN OUT'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
