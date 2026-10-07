import 'package:supabase_flutter/supabase_flutter.dart';

class AdminAuthChange {
  const AdminAuthChange(this.userId, {this.isTokenRefresh = false});

  final String? userId;
  final bool isTokenRefresh;
}

abstract class AdminAuthService {
  String? get currentUserId;
  Stream<AdminAuthChange> get userChanges;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });
  Future<bool> isAdmin(String userId);
  Future<void> signOut();
}

class SupabaseAdminAuthService implements AdminAuthService {
  SupabaseAdminAuthService({
    SupabaseClient? client,
    Duration roleLookupTimeout = const Duration(seconds: 15),
  })  : _client = client ?? Supabase.instance.client,
        _roleLookupTimeout = roleLookupTimeout;

  final SupabaseClient _client;
  final Duration _roleLookupTimeout;

  @override
  String? get currentUserId => _client.auth.currentSession?.user.id;

  @override
  Stream<AdminAuthChange> get userChanges =>
      _client.auth.onAuthStateChange.map((state) => AdminAuthChange(
            state.session?.user.id,
            isTokenRefresh: state.event == AuthChangeEvent.tokenRefreshed,
          ));

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<bool> isAdmin(String userId) async {
    final profile = await _client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle()
        .timeout(_roleLookupTimeout);
    return profile?['role'] == 'admin';
  }

  @override
  Future<void> signOut() => _client.auth.signOut(scope: SignOutScope.local);
}
