import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'analytics_service.dart';
import 'app_theme.dart';
import 'screens/home_page.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

  try {
    await Supabase.initialize(url: url, anonKey: anonKey);
  } catch (_) {
    // Supabase is optional for Viewer startup. Cloudflare/GitHub fallbacks
    // keep the public match list usable on restricted networks.
  }
  try {
    await AppThemeController.instance.load();
  } catch (_) {}
  await AnalyticsService.initialize();

  runApp(const FootballViewerApp());
}

class FootballViewerApp extends StatelessWidget {
  const FootballViewerApp({super.key});

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
          home: const HomePage(),
        );
      },
    );
  }
}
