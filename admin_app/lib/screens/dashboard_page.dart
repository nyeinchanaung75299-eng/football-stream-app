import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_upload_page.dart';
import 'live_links_page.dart';
import 'edit_live_page.dart';
import 'highlights_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void open(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 92,
        backgroundColor: const Color(0xFF263238),
        foregroundColor: Colors.white,
        title: const Text(
          'Football Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Live Management',
            titleIcon: Icons.live_tv,
            titleColor: Colors.redAccent,
            items: [
              _MenuItem(
                icon: Icons.add_circle_outline,
                text: 'Upload Live',
                onTap: () => open(context, const LiveUploadPage()),
              ),
              _MenuItem(
                icon: Icons.link,
                text: 'Upload Live Links',
                onTap: () => open(context, const LiveLinksPage()),
              ),
              _MenuItem(
                icon: Icons.edit_document,
                text: 'Edit & Delete Live',
                onTap: () => open(context, const EditLivePage()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Highlights Management',
            titleIcon: Icons.play_circle_fill,
            titleColor: Colors.orange,
            items: [
              _MenuItem(
                icon: Icons.add_box_outlined,
                text: 'Upload Highlight',
                onTap: () => open(context, const HighlightsPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.titleIcon,
    required this.titleColor,
    required this.items,
  });

  final String title;
  final IconData titleIcon;
  final Color titleColor;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(
              children: [
                Icon(titleIcon, color: titleColor, size: 30),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...items.map((item) => Column(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Icon(item.icon, size: 30),
                    title: Text(
                      item.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: item.onTap,
                  ),
                  if (item != items.last)
                    const Divider(height: 1, indent: 64, endIndent: 16),
                ],
              )),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
}
