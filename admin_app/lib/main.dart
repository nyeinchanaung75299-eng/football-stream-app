import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'backend_endpoint.dart';
import 'app_theme.dart';
import 'screens/auth_gate.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const directUrl = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

  final url = await resolveSupabaseUrl(
    directUrl: directUrl,
    publishableKey: anonKey,
  );

  await Future.wait([
    Supabase.initialize(url: url, anonKey: anonKey),
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
