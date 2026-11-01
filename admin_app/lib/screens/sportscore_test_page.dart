import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// An isolated, read-only preview. Never imports fixtures into NCA.
class SportScoreTestPage extends StatefulWidget {
  const SportScoreTestPage({super.key});

  @override
  State<SportScoreTestPage> createState() => _SportScoreTestPageState();
}

class _SportScoreTestPageState extends State<SportScoreTestPage> {
  static const _leagues = <String, String>{
    'saudi-professional-league': 'Saudi Pro League',
    'united-states-major-league-soccer': 'MLS',
    'english-premier-league': 'Premier League',
    'uefa-champions-league': 'Champions League',
  };

  static DateTime _todayInMyanmar() {
    final now = DateTime.now().toUtc().add(const Duration(minutes: 390));
    return DateTime(now.year, now.month, now.day);
  }

  String _league = 'saudi-professional-league';
  DateTime _date = _todayInMyanmar();
  bool _loading = false;
  bool _loaded = false;
  bool _possiblyTruncated = false;
  int _requestVersion = 0;
  String? _error;
  List<Map<String, dynamic>> _matches = [];

  @override
  void dispose() {
    _requestVersion++;
    super.dispose();
  }

  void _clearPreviousResults() {
    _requestVersion++;
    _loaded = false;
    _possiblyTruncated = false;
    _matches = [];
    _error = null;
  }

  Future<void> _pickDate() async {
    if (_loading) return;
    final today = _todayInMyanmar();
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 180)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date = selected;
      _clearPreviousResults();
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _loaded = false;
      _error = null;
      _matches = [];
    });
    try {
      // Direct authenticated invocation: no change to existing ColaTV
      // source selection, fallback chain, or custom proxy routes.
      final response = await Supabase.instance.client.functions.invoke(
        'sportscore-test',
        body: {
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'competition': _league,
        },
      );
      final data = response.data;
      if (data is! Map || data['matches'] is! List ||
          data['preview_only'] != true || data['provider'] != 'sportscore') {
        throw const FormatException('Invalid SportScore preview response.');
      }
      final matches = (data['matches'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted || _requestVersion != version) return;
      setState(() {
        _matches = matches;
        _possiblyTruncated = data['possibly_truncated'] == true;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted || _requestVersion != version) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && _requestVersion == version) {
        setState(() => _loading = false);
      }
    }
  }

  String _myanmarKickoff(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'Unknown kickoff';
    final myanmar = parsed.toUtc().add(const Duration(minutes: 390));
    return "${DateFormat('MMM d, h:mm a').format(myanmar)} MMT";
  }

  Widget _matchTile(Map<String, dynamic> match) {
    final home = match['home']?.toString() ?? '?';
    final away = match['away']?.toString() ?? '?';
    final homeScore = match['home_score'];
    final awayScore = match['away_score'];
    final score = homeScore == null || awayScore == null
        ? 'vs'
        : '$homeScore - $awayScore';
    final status = match['status']?.toString() ?? 'unknown';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$home   $score   $away',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${_myanmarKickoff(match['kickoff_at'])}  •  $status',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = DateFormat('EEE, d MMM yyyy').format(_date);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('SportScore Test Schedule')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: colors.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'TESTING ONLY — Admin preview. No fixture imports, '
                'no changes to Cola TV, database, or User App.',
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _league,
            decoration: const InputDecoration(
              labelText: 'Competition',
              border: OutlineInputBorder(),
            ),
            items: _leagues.entries
                .map((entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ))
                .toList(),
            onChanged: _loading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _league = value;
                      _clearPreviousResults();
                    });
                  },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Myanmar date: $selectedDate'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Load Test Fixtures'),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              'Could not load preview: $_error',
              style: TextStyle(color: colors.error),
            ),
            const Text(
              'Ensure the sportscore-test Edge Function has been deployed. '
              'This does not affect existing NCA fixtures.',
            ),
          ],
          if (_loaded) ...[
            const SizedBox(height: 16),
            Text(
              '${_matches.length} fixtures • ${_leagues[_league]} • Myanmar date',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_possiblyTruncated)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Warning: SportScore hit the 200-match UTC-day limit; '
                  'this list might be incomplete.',
                ),
              ),
            if (_matches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('No fixtures returned for this date and league.'),
              ),
            ..._matches.map(_matchTile),
          ],
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Powered by SportScore'),
              onPressed: () async {
                await launchUrl(
                  Uri.parse('https://sportscore.com/'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ),
          const Text(
            'For testing only. Confirm SportScore attribution/licensing '
            'terms before any production or public release.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
