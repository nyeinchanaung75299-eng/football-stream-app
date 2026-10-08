import 'dart:async';
import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'screens/home_page.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backendReady = _initializeBackend();
  runApp(FootballViewerApp(backendReady: backendReady));

  // Render the app before optional network/storage setup finishes.
  unawaited(_loadTheme());
  unawaited(AnalyticsService.initialize());
}

Future<void> _initializeBackend() async {
  const directUrl = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

  try {
    final url = await resolveSupabaseUrl(
      directUrl: directUrl,
      publishableKey: anonKey,
    );
    await Supabase.initialize(url: url, anonKey: anonKey);
  } catch (_) {
    // Supabase is optional for Viewer startup. Cloudflare/Vercel fallbacks
    // keep the public match list usable on restricted networks.
  }
}

Future<void> _loadTheme() async {
  try {
    await AppThemeController.instance.load();
  } catch (_) {}
}

class FootballViewerApp extends StatelessWidget {
  const FootballViewerApp({super.key, this.backendReady});

  final Future<void>? backendReady;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'NCA',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemeController.instance.mode,
          navigatorObservers: [PosthogObserver()],
          home: HomePage(backendReady: backendReady),
        );
      },
    );
  }
}
