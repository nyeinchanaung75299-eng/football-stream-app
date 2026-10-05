import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../analytics_service.dart';

class LiveUploadPage extends StatefulWidget {
  const LiveUploadPage({super.key});

  @override
  State<LiveUploadPage> createState() => _LiveUploadPageState();
}

class _LiveUploadPageState extends State<LiveUploadPage> {
  final league = TextEditingController();
  final homeTeam = TextEditingController();
  final awayTeam = TextEditingController();
  final homeLogo = TextEditingController();
  final awayLogo = TextEditingController();
  final order = TextEditingController(text: '0');

  DateTime kickoff = DateTime.now().add(const Duration(hours: 1));
  bool isLive = false;
  bool loading = false;

  Future<void> pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: kickoff,
    );
    if (result != null) {
      setState(() {
        kickoff = DateTime(
          result.year,
          result.month,
          result.day,
          kickoff.hour,
          kickoff.minute,
        );
      });
    }
  }

  Future<void> pickTime() async {
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(kickoff),
    );
    if (result != null) {
      setState(() {
        kickoff = DateTime(
          kickoff.year,
          kickoff.month,
          kickoff.day,
          result.hour,
          result.minute,
        );
      });
    }
  }

  Future<void> save() async {
    if (league.text.trim().isEmpty ||
        homeTeam.text.trim().isEmpty ||
        awayTeam.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League and team names are required.')),
      );
      return;
    }

    setState(() => loading = true);
    try {
      await Supabase.instance.client.from('matches').insert({
        'league': league.text.trim(),
        'home_team': homeTeam.text.trim(),
        'away_team': awayTeam.text.trim(),
        'home_logo_url':
            homeLogo.text.trim().isEmpty ? null : homeLogo.text.trim(),
        'away_logo_url':
            awayLogo.text.trim().isEmpty ? null : awayLogo.text.trim(),
        'kickoff_at': kickoff.toUtc().toIso8601String(),
        'sort_order': int.tryParse(order.text) ?? 0,
        'is_live': isLive,
        'is_active': true,
        'is_featured': true,
        'publish_state': 'published',
        'source': 'manual',
        'status_short': isLive ? 'LIVE' : 'NS',
      });

      await AnalyticsService.capture(
        'manual match created',
        properties: {
          'is_live': isLive,
          'has_home_logo': homeLogo.text.trim().isNotEmpty,
          'has_away_logo': awayLogo.text.trim().isNotEmpty,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live match uploaded.')),
      );
      Navigator.pop(context);
    } catch (e) {
      await AnalyticsService.capture(
        'manual match create failed',
        properties: {'is_live': isLive},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Live Match')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _Section(
            icon: Icons.emoji_events_outlined,
            title: 'Match details',
            child: Column(
              children: [
                TextField(
                  controller: league,
                  decoration: const InputDecoration(
                    labelText: 'League',
                    hintText: 'Premier League',
                    prefixIcon: Icon(Icons.emoji_events_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: homeTeam,
                        decoration: const InputDecoration(
                          labelText: 'Home team',
                          prefixIcon: Icon(Icons.home_filled),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: awayTeam,
                        decoration: const InputDecoration(
                          labelText: 'Away team',
                          prefixIcon: Icon(Icons.flight_takeoff_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.image_outlined,
            title: 'Team logos',
            subtitle: 'Paste direct .png/.jpg links — no gallery upload.',
            child: Column(
              children: [
                TextField(
                  controller: homeLogo,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Home logo URL',
                    hintText: 'https://.../home.png',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: awayLogo,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Away logo URL',
                    hintText: 'https://.../away.png',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            icon: Icons.schedule_rounded,
            title: 'Schedule',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(
                          DateFormat('dd MMM yyyy').format(kickoff),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: pickTime,
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text(DateFormat('HH:mm').format(kickoff)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Display order',
                    prefixIcon: Icon(Icons.format_list_numbered_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text(
                    'Mark as LIVE now',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isLive
                        ? 'The LIVE badge will be shown immediately.'
                        : 'You can turn this on later.',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  value: isLive,
                  onChanged: (v) => setState(() => isLive = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : save,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            label: Text(loading ? 'UPLOADING...' : 'UPLOAD LIVE MATCH'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: .5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colors.primary, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                subtitle!,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
