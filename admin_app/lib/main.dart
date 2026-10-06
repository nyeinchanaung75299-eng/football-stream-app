import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'screens/auth_gate.dart';
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
  Future<String?> accessToken() async =>
      _preferences.getString(_sessionKey);

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

  const directUrl = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

  final url = await resolveSupabaseUrl(
    directUrl: directUrl,
    publishableKey: anonKey,
  );

  await Future.wait([
    Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: _StableAdminSessionStorage(),
      ),
    ),
    AppThemeController.instance.load(),
  ]);
  await AnalyticsService.initialize();

  runApp(const FootballAdminApp());
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
          home: const AuthGate(),
        );
      },
    );
  }
}
