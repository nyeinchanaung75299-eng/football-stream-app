import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'screens/home_page.dart';
import 'theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = 'https://woggzixprvyjnfjzsglz.supabase.co';
  const anonKey = 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O';

  await Future.wait([
    Supabase.initialize(url: url, anonKey: anonKey),
    AppThemeController.instance.load(),
  ]);

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
          title: 'Football Live',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppThemeController.instance.mode,
          home: const HomePage(),
        );
      },
    );
  }
}
