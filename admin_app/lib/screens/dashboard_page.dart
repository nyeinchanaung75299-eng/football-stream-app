import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../services/tv_schedule_service.dart';
import '../services/admin_web_source_cache.dart';
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
  // Tabs are mounted only when first visited, then retained for instant
  // re-entry. This dashboard is keyed to the verified Admin user/session.
  final Set<int> _visitedTabs = {0};
  int _guideRevision = 0;
  static const _mutatingSections = <String>{
    'manual-match', 'stream-servers', 'matches-scores',
    'upload-channels', 'channel-management', 'channel-health',
    'connected-channels', 'livetv-sports', 'deleted-source-lines',
    'epg-discrepancies', 'stream-sources',
  };

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
    unawaited(Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/admin/$section'),
        builder: (_) => page,
      ),
    ).then((_) {
      if (!mounted || !_mutatingSections.contains(section)) return;
      // Web has explicit success callbacks for the source picker. Do not
      // evict guides simply because an Admin previewed a provider.
      if (kIsWeb && section == 'stream-sources') return;
      // The editing route may have changed fixtures or channels. Evict only
      // dependent guide screens, never hold a deleted row in an Admin cache.
      _invalidateGuidesAfterEdit();
    }));
  }

  void _invalidateGuidesAfterEdit() {
    if (!mounted) return;
    TvScheduleService.invalidateShared();
    setState(() {
      _guideRevision++;
      _visitedTabs.removeAll({3, 4});
    });
  }

  Widget _tabContent(int index, ColorScheme colors) => SafeArea(
    top: index != 0,
    bottom: false,
    child: switch (index) {
      0 => _controls(context, colors),
      1 => StreamSourcePickerPage(
        embedded: true,
        onSourceMutated: _invalidateGuidesAfterEdit,
      ),
      2 => _tools(context, colors),
      3 => TvSchedulesPage(
        key: ValueKey('admin-tv-$_guideRevision'),
        embedded: true,
        active: _tab == 3,
      ),
      _ => MyChannelsGuidePage(
        key: ValueKey('admin-channels-$_guideRevision'),
        embedded: true,
        active: _tab == 4,
      ),
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: _tab == 0 ? AppBar(
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
              if (kIsWeb) {
                AdminWebSourceCache.clear();
                TvScheduleService.invalidateShared();
              }
              await Supabase.instance.client.auth.signOut();
              // The old private widget tree is destroyed by AuthGate on
              // sign-out; clear the session-scoped tab registry as well.
              if (mounted) setState(() {
                _visitedTabs.clear();
                _tab = 0;
              });
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ) : null,
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
          setState(() {
            _tab = index;
            _visitedTabs.add(index);
          });
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
      // Lazy Offstage: never mount unseen tabs, retain successful data,
      // dropdowns, scroll offsets and form state for every visited tab.
      // Using a normal eager IndexedStack here would fetch private Admin
      // guides before an authorized user explicitly enters those tabs.
      body: Stack(
        children: [
          for (final index in (_visitedTabs.toList()..sort()))
            Offstage(
              key: ValueKey('admin-tab-$index'),
              offstage: index != _tab,
              child: TickerMode(
                enabled: index == _tab,
                child: _tabContent(index, colors),
              ),
            ),
        ],
      ),
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
            open(context, FixtureImportPage(
              onPublished: kIsWeb ? _invalidateGuidesAfterEdit : null,
            ), 'pick-big-matches'),
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
          RepositoryMatchesPage(
            onMutated: kIsWeb ? _invalidateGuidesAfterEdit : null,
          ),
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
