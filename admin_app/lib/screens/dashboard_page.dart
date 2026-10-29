import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../widgets/theme_mode_button.dart';
import 'edit_live_page.dart';
import 'fixture_import_page.dart';
import 'live_links_page.dart';
import 'live_upload_page.dart';
import 'soco_import_page.dart';
import 'channels_page.dart';
import 'my_channels_guide_page.dart';
import 'system_health_page.dart';
import 'tv_schedules_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;

  void open(BuildContext context, Widget page, String section) {
    AnalyticsService.capture(
      'admin section opened',
      properties: {'section': section},
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: '/admin/$section'),
        builder: (_) => page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('NCA Admin'),
        actions: [
          const ThemeModeButton(),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await AnalyticsService.capture('admin logout');
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) {
          if (index == _tab) return;
          final section = switch (index) {
            0 => 'controls',
            1 => 'my-channels',
            2 => 'tv-schedule',
            _ => 'system-health',
          };
          AnalyticsService.capture(
            'admin section opened',
            properties: {'section': section, 'entry': 'bottom_navigation'},
          );
          setState(() => _tab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Controls',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv_rounded),
            label: 'My Channels',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'TV Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart_rounded),
            label: 'System Health',
          ),
        ],
      ),
      // Do not use an eager IndexedStack here: My Channels and TV Schedule
      // both read Admin data and must not make a request until the user opens
      // the matching bottom tab.
      body: switch (_tab) {
        0 => _controls(context, colors),
        1 => const MyChannelsGuidePage(embedded: true),
        2 => const TvSchedulesPage(embedded: true),
        _ => const SystemHealthPage(active: true),
      },
    );
  }

  Widget _controls(BuildContext context, ColorScheme colors) => ListView(
    key: const PageStorageKey('admin-controls'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 22),
    children: [
      Text(
        'Control Center',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4),
      ),
      const SizedBox(height: 10),
      _ActionCard(
        icon: Icons.star_rounded,
        title: 'Pick Big Matches',
        subtitle:
            'Choose fixtures from the API and publish only selected games.',
        iconColor: const Color(0xFFF59E0B),
        onTap: () =>
            open(context, const FixtureImportPage(), 'pick-big-matches'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.add_circle_outline_rounded,
        title: 'Upload Live',
        subtitle: 'Create a live match with teams, logos and kickoff time.',
        iconColor: const Color(0xFF0EA5E9),
        onTap: () => open(context, const LiveUploadPage(), 'manual-match'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.link_rounded,
        title: 'Upload Live Links',
        subtitle: 'Choose a match and manage its approved stream links.',
        iconColor: const Color(0xFF7C3AED),
        onTap: () => open(context, const LiveLinksPage(), 'stream-servers'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.sports_score_rounded,
        title: 'Edit & Delete Live',
        subtitle: 'Edit teams, kickoff or live state, and delete a match.',
        iconColor: colors.primary,
        onTap: () => open(context, const EditLivePage(), 'matches-scores'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.tv_rounded,
        title: 'Channel Manager',
        subtitle: 'Edit your TV channels, images and visibility.',
        iconColor: colors.primary,
        onTap: () => open(context, const ChannelsPage(), 'channels'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.podcasts_rounded,
        title: 'Stream Source Picker',
        subtitle: 'Open sources and your private manual HLS library.',
        iconColor: const Color(0xFFDC2626),
        onTap: () =>
            open(context, const SocoImportPage(), 'stream-source-picker'),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.25,
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
