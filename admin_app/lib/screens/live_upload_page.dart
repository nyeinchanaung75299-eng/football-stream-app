import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live match uploaded.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Upload')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: league,
                    decoration: const InputDecoration(
                      labelText: 'Select / Enter League',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: homeTeam,
                          decoration:
                              const InputDecoration(labelText: 'H-Team Name'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: awayTeam,
                          decoration:
                              const InputDecoration(labelText: 'A-Team Name'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: homeLogo,
                          decoration: const InputDecoration(
                            labelText: 'H-Team Logo URL',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: awayLogo,
                          decoration: const InputDecoration(
                            labelText: 'A-Team Logo URL',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickDate,
                          icon: const Icon(Icons.calendar_month),
                          label: Text(DateFormat('yyyy-MM-dd').format(kickoff)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pickTime,
                          icon: const Icon(Icons.schedule),
                          label: Text(DateFormat('HH:mm').format(kickoff)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Order'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark as LIVE now'),
                    value: isLive,
                    onChanged: (v) => setState(() => isLive = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: loading ? null : save,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(loading ? 'UPLOADING...' : 'UPLOAD LIVE'),
            ),
          ),
        ],
      ),
    );
  }
}
