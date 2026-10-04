import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/theme_mode_button.dart';
import 'edit_live_page.dart';
import 'fixture_import_page.dart';
import 'live_links_page.dart';
import 'live_upload_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Football Admin'),
        actions: [
          const ThemeModeButton(),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF0F5132),
                  Color(0xFF16A34A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF16A34A).withValues(alpha: .18),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Match Manager',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.4,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Pick fixtures from the football API or create your own match.',
                        style: TextStyle(
                          color: Color(0xFFE5F7EB),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                _HeroBall(),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Add Matches',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.event_available_rounded,
            title: 'Pick Football Fixtures',
            subtitle:
                'Load today, tomorrow or live matches and add only the games you want.',
            iconColor: colors.primary,
            onTap: () => open(context, const FixtureImportPage()),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.edit_calendar_rounded,
            title: 'Create Match Manually',
            subtitle:
                'Type the teams yourself and use your own logo URLs when needed.',
            iconColor: const Color(0xFF0EA5E9),
            onTap: () => open(context, const LiveUploadPage()),
          ),
          const SizedBox(height: 24),
          Text(
            'Manage',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.2,
                ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.link_rounded,
            title: 'Live Links',
            subtitle: 'Add, edit, disable or delete stream servers.',
            iconColor: const Color(0xFF6D5DFB),
            onTap: () => open(context, const LiveLinksPage()),
          ),
          const SizedBox(height: 10),
          _ActionCard(
            icon: Icons.tune_rounded,
            title: 'Edit Matches',
            subtitle:
                'Fix team names, logos, date/time, LIVE status or delete a match.',
            iconColor: const Color(0xFFF59E0B),
            onTap: () => open(context, const EditLivePage()),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Supabase connected • Imported and manual matches use the same match list.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBall extends StatelessWidget {
  const _HeroBall();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: const Icon(
        Icons.sports_soccer_rounded,
        color: Colors.white,
        size: 42,
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
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
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
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 17,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
