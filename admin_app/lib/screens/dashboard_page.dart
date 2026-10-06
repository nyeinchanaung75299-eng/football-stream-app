import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../analytics_service.dart';
import '../widgets/theme_mode_button.dart';
import 'edit_live_page.dart';
import 'fixture_import_page.dart';
import 'highlights_page.dart';
import 'live_links_page.dart';
import 'live_upload_page.dart';
import 'soco_import_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(
    BuildContext context,
    Widget page,
    String section,
  ) {
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Text(
            'Control Center',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Only the controls you need.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _ActionCard(
            icon: Icons.star_rounded,
            title: 'Pick Big Matches',
            subtitle: 'Choose fixtures from the API and publish only selected games.',
            iconColor: const Color(0xFFF59E0B),
            onTap: () => open(
              context,
              const FixtureImportPage(),
              'pick-big-matches',
            ),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.add_circle_outline_rounded,
            title: 'Manual Match',
            subtitle: 'Create your own match and use your own logo URLs.',
            iconColor: const Color(0xFF0EA5E9),
            onTap: () => open(
              context,
              const LiveUploadPage(),
              'manual-match',
            ),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.sports_score_rounded,
            title: 'Matches & Scores',
            subtitle: 'Edit score, teams, logos, kickoff, publish state or delete.',
            iconColor: colors.primary,
            onTap: () => open(
              context,
              const EditLivePage(),
              'matches-scores',
            ),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.dns_rounded,
            title: 'Stream Servers',
            subtitle: 'Add primary/backup links and edit or disable them.',
            iconColor: const Color(0xFF7C3AED),
            onTap: () => open(
              context,
              const LiveLinksPage(),
              'stream-servers',
            ),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.podcasts_rounded,
            title: 'Soco / YYZB / Fawa / ColaTV Links',
            subtitle: 'Extract M3U8 / MPD / FLV / MP4 source links and add them to a match.',
            iconColor: const Color(0xFFDC2626),
            onTap: () => open(
              context,
              const SocoImportPage(),
              'stream-source-picker',
            ),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.video_library_rounded,
            title: 'Highlights Management',
            subtitle: 'Upload highlight title, thumbnail and video URL.',
            iconColor: const Color(0xFFF97316),
            onTap: () => open(
              context,
              const HighlightsPage(),
              'highlights',
            ),
          ),
        ],
      ),
    );
  }
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
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.35,
                        fontSize: 13,
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
