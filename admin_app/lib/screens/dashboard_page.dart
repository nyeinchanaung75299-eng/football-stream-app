import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../admin_update_service.dart';
import '../widgets/theme_mode_button.dart';
import 'channels_page.dart';
import 'connected_channels_page.dart';
import 'channel_health_page.dart';
import 'edit_live_page.dart';
import 'fixture_import_page.dart';
import 'live_links_page.dart';
import 'live_upload_page.dart';
import 'my_channels_guide_page.dart';
import 'stream_source_picker_page.dart';
import 'tv_schedules_page.dart';
import 'telegram_setup_page.dart';
import 'repository_matches_page.dart';
import 'epg_discrepancies_page.dart';
import 'suppressed_source_lines_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // No background polling: once when Admin opens, plus the manual button.
        // An update still requires explicit confirmation to install.
        AdminUpdateService.check(context, automatic: true);
      }
    });
  }

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
          IconButton(
            tooltip: 'Check Admin APK update',
            icon: const Icon(Icons.system_update_alt_rounded),
            onPressed: () => AdminUpdateService.check(context),
          ),
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
            1 => 'stream-sources',
            2 => 'tools',
            3 => 'tv-schedule',
            _ => 'my-channels',
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
            icon: Icon(Icons.podcasts_outlined),
            selectedIcon: Icon(Icons.podcasts_rounded),
            label: 'Sources',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'TV Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv_rounded),
            label: 'My Channels',
          ),
        ],
      ),
      // Do not use an eager IndexedStack here: My Channels and TV Schedule
      // both read Admin data and must not make a request until the user opens
      // the matching bottom tab.
      body: switch (_tab) {
        0 => _controls(context, colors),
        1 => const StreamSourcePickerPage(embedded: true),
        2 => _tools(context, colors),
        3 => const TvSchedulesPage(embedded: true),
        _ => const MyChannelsGuidePage(embedded: true),
      },
    );
  }

  Widget _controls(BuildContext context, ColorScheme colors) => ListView(
    key: const PageStorageKey('admin-controls'),
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 22),
    children: [
      Text(
        'Live Management',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4),
      ),
      const SizedBox(height: 12),
      _ActionCard(
        icon: Icons.star_rounded,
        title: 'Pick Big Matches',
        iconColor: const Color(0xFFF59E0B),
        onTap: () =>
            open(context, const FixtureImportPage(), 'pick-big-matches'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.add_circle_outline_rounded,
        title: 'Upload Live',
        iconColor: const Color(0xFF0EA5E9),
        onTap: () => open(context, const LiveUploadPage(), 'manual-match'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.link_rounded,
        title: 'Upload Live Links',
        iconColor: const Color(0xFF7C3AED),
        onTap: () => open(context, const LiveLinksPage(), 'stream-servers'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.sports_score_rounded,
        title: 'Edit & Delete Live',
        iconColor: colors.primary,
        onTap: () => open(context, const EditLivePage(), 'matches-scores'),
      ),
      const SizedBox(height: 8),
      const SizedBox(height: 12),
      Text(
        'Channel Management',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.add_circle_outline_rounded,
        title: 'Upload Channels',
        iconColor: const Color(0xFF54E6C1),
        onTap: () => open(context, const ChannelUploadPage(), 'upload-channels'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.edit_note_rounded,
        title: 'Edit & Delete Channels',
        iconColor: const Color(0xFF6099FF),
        onTap: () => open(context, const ChannelsPage(), 'channel-management'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Channel Health',
        iconColor: const Color(0xFF10B981),
        onTap: () => open(context, const ChannelHealthPage(), 'channel-health'),
      ),
    ],
  );

  Widget _tools(BuildContext context, ColorScheme colors) => ListView(
    key: const PageStorageKey('admin-tools'),
    padding: const EdgeInsets.fromLTRB(12, 14, 12, 22),
    children: [
      Text(
        'Tools',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.4),
      ),
      const SizedBox(height: 12),
      _ActionCard(
        icon: Icons.sports_soccer_rounded,
        title: 'Repository Matches',
        iconColor: colors.primary,
        onTap: () => open(
          context,
          const RepositoryMatchesPage(),
          'repository-matches',
        ),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.sync_rounded,
        title: 'DarkByte Channels',
        iconColor: const Color(0xFF54E6C1),
        onTap: () => open(context, const ConnectedChannelsPage(), 'connected-channels'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.sports_soccer_rounded,
        title: 'LiveTV Sports',
        iconColor: const Color(0xFF54E6C1),
        onTap: () => open(context, const ConnectedChannelsPage(sportsOnly: true), 'livetv-sports'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.restore_rounded,
        title: 'Deleted source lines • Allow again',
        iconColor: const Color(0xFF6099FF),
        onTap: () => open(context, const SuppressedSourceLinesPage(), 'deleted-source-lines'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.report_problem_outlined,
        title: 'EPG mismatch reports',
        iconColor: const Color(0xFFF59E0B),
        onTap: () => open(context, const EpgDiscrepanciesPage(), 'epg-discrepancies'),
      ),
      const SizedBox(height: 8),
      _ActionCard(
        icon: Icons.send_rounded,
        title: 'Connect Telegram Bots',
        iconColor: const Color(0xFF54E6C1),
        onTap: () => open(context, const TelegramSetupPage(), 'telegram-bots'),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
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
