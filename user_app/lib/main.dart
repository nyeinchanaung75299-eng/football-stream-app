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

  Object? startupError;
  try {
    await Supabase.initialize(url: url, anonKey: anonKey);
  } catch (e) {
    startupError = e;
  }
  try {
    await AppThemeController.instance.load();
  } catch (_) {}
  await AnalyticsService.initialize();

  runApp(FootballViewerApp(startupError: startupError));
}

class FootballViewerApp extends StatelessWidget {
  const FootballViewerApp({super.key, this.startupError});
  final Object? startupError;

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
          home: startupError == null ? const HomePage() : const _StartupErrorPage(),
        );
      },
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 60),
                SizedBox(height: 14),
                Text('Server connection unavailable', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('Check your internet connection or try another network, then reopen the app.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
