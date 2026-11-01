import 'dart:async';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'screens/auth_gate.dart';
import 'screens/startup_gate.dart';
import 'theme_controller.dart';

class _StableAdminSessionStorage extends LocalStorage {
  static const _sessionKey = 'nca_admin_auth_session_v1';

  // Supabase's default Flutter auth storage key is derived from the client
  // URL. This app can start through either the direct project URL or one of
  // the VPN-free relay hostnames, so migrate sessions saved under the common
  // legacy/default keys into one endpoint-independent key.
  static const _legacyKeys = <String>[
    'sb-woggzixprvyjnfjzsglz-auth-token',
    'sb-supabase-api-auth-token',
    'SUPABASE_PERSIST_SESSION_KEY',
  ];

  late SharedPreferences _preferences;

  @override
  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    final current = _preferences.getString(_sessionKey);
    if (current != null && current.isNotEmpty) return;

    for (final key in _legacyKeys) {
      final value = _preferences.getString(key);
      if (value == null || value.isEmpty) continue;
      await _preferences.setString(_sessionKey, value);
      return;
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final value = _preferences.getString(_sessionKey);
    return value != null && value.isNotEmpty;
  }

  @override
  Future<String?> accessToken() async => _preferences.getString(_sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _preferences.setString(_sessionKey, persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    await _preferences.remove(_sessionKey);
    for (final key in _legacyKeys) {
      await _preferences.remove(key);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FootballAdminApp());
  unawaited(_loadTheme());
  unawaited(AnalyticsService.initialize());
}

Future<void> _loadTheme() async {
  try {
    await AppThemeController.instance.load();
  } catch (_) {}
}

Future<void>? _backendInitialization;

bool _backendIsInitialized() {
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _initializeBackend() =>
    _backendInitialization ??= _initializeBackendOnce();

Future<void> _initializeBackendOnce() async {
  const directUrl = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';
  try {
    // Remember only a previously verified Auth route. Each startup still
    // re-probes it; a stale VPN/network path cannot bypass the health check.
    const routeKey = 'nca_admin_auth_route_v1';
    SharedPreferences? preferences;
    String? preferred;
    try {
      preferences = await SharedPreferences.getInstance();
      preferred = preferences.getString(routeKey);
    } catch (_) {
      // Private storage might be unavailable; connection still proceeds.
    }
    final url = await resolveSupabaseUrl(
      directUrl: directUrl,
      publishableKey: anonKey,
      preferredBase: preferred,
    );
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: _StableAdminSessionStorage(),
      ),
    );
    if (preferences != null) {
      try {
        unawaited(preferences.setString(routeKey, url).catchError((_) => false));
      } catch (_) {
        // A storage failure must not delay a verified Admin Auth route.
      }
    }
  } catch (_) {
    // Some SDK failures happen after the client is constructed (for example,
    // a stored session cannot be restored over the current network). Let the
    // AuthGate recover through its login flow instead of retrying initialization.
    if (_backendIsInitialized()) return;
    // A genuine completed failure can be retried. A UI timeout does not reach
    // this branch, so the same in-flight initialization remains memoized.
    _backendInitialization = null;
    rethrow;
  }
}

class FootballAdminApp extends StatelessWidget {
  const FootballAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'NCA Admin',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemeController.instance.mode,
          navigatorObservers: [PosthogObserver()],
          home: const StartupGate(
              initialize: _initializeBackend, child: AuthGate()),
        );
      },
    );
  }
}
