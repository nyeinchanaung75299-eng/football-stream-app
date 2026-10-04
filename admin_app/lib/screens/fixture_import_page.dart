import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureImportPage extends StatefulWidget {
  const FixtureImportPage({super.key});

  @override
  State<FixtureImportPage> createState() => _FixtureImportPageState();
}

class _FixtureImportPageState extends State<FixtureImportPage> {
  DateTime selectedDate = DateTime.now();
  String mode = 'date';
  bool loading = false;
  bool importing = false;
  String? errorText;

  List<Map<String, dynamic>> fixtures = [];
  final Set<int> selectedIds = {};

  Future<void> pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: selectedDate,
    );

    if (result == null) return;

    setState(() {
      selectedDate = result;
      mode = 'date';
    });

    await loadFixtures();
  }

  Future<void> loadFixtures() async {
    setState(() {
      loading = true;
      errorText = null;
      selectedIds.clear();
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'football-fixtures',
        body: {
          'mode': mode,
          'date': DateFormat('yyyy-MM-dd').format(selectedDate),
        },
      );

      final data = response.data;
      if (data is! Map) {
        throw Exception('Unexpected API response.');
      }

      if (data['error'] != null) {
        throw Exception(data['error'].toString());
      }

      final rows = data['fixtures'];
      if (rows is! List) {
        throw Exception('No fixture list returned.');
      }

      if (!mounted) return;
      setState(() {
        fixtures = rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        fixtures = [];
        final raw = e.toString();
        errorText = raw.contains('API_FOOTBALL_KEY') || raw.contains('FOOTBALL_API_KEY_MISSING')
            ? 'Football API is not connected. Check API_FOOTBALL_KEY in Supabase Edge Functions > Secrets.'
            : 'Could not load fixtures. Please try again.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void toggleFixture(int id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  Future<void> importSelected() async {
    final chosen = fixtures
        .where((f) => selectedIds.contains(f['fixture_id'] as int))
        .toList();

    if (chosen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one match.')),
      );
      return;
    }

    setState(() => importing = true);

    try {
      for (final f in chosen) {
        await Supabase.instance.client.from('matches').upsert(
          {
            'external_fixture_id': f['fixture_id'],
            'source': 'api_football',
            'league': f['league_name'],
            'home_team': f['home_name'],
            'away_team': f['away_name'],
            'home_logo_url': f['home_logo'],
            'away_logo_url': f['away_logo'],
            'kickoff_at': f['kickoff_at'],
            'home_score': f['home_score'],
            'away_score': f['away_score'],
            'status_short': f['status_short'] ?? 'NS',
            'status_elapsed': f['status_elapsed'],
            'is_finished': f['is_finished'] == true,
            'is_live': f['is_live'] == true,
            'is_active': true,
            'is_featured': true,
            'publish_state': 'published',
          },
          onConflict: 'external_fixture_id',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${chosen.length} match${chosen.length == 1 ? '' : 'es'} added.',
          ),
        ),
      );

      setState(() => selectedIds.clear());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Widget modeButton({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final active = mode == value;

    return Expanded(
      child: active
          ? FilledButton.icon(
              onPressed: () async {
                setState(() => mode = value);
                await loadFixtures();
              },
              icon: Icon(icon, size: 18),
              label: Text(label),
            )
          : OutlinedButton.icon(
              onPressed: () async {
                setState(() => mode = value);
                await loadFixtures();
              },
              icon: Icon(icon, size: 18),
              label: Text(label),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Big Matches'),
      ),
      bottomNavigationBar: selectedIds.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: importing ? null : importSelected,
                  icon: importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_task_rounded),
                  label: Text(
                    importing
                        ? 'ADDING...'
                        : 'PUBLISH SELECTED (${selectedIds.length})',
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Only the matches you tick are published as featured matches. The viewer will not list the rest.',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              modeButton(
                value: 'date',
                label: 'Date',
                icon: Icons.calendar_month_rounded,
              ),
              const SizedBox(width: 8),
              modeButton(
                value: 'live',
                label: 'Live',
                icon: Icons.podcasts_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (mode == 'date')
            OutlinedButton.icon(
              onPressed: pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text(
                DateFormat('EEE, dd MMM yyyy').format(selectedDate),
              ),
            ),
          const SizedBox(height: 10),
          if (fixtures.isEmpty && !loading)
            FilledButton.tonalIcon(
              onPressed: loadFixtures,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('LOAD MATCHES'),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (errorText != null && !loading)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 38),
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: loadFixtures,
                      child: const Text('TRY AGAIN'),
                    ),
                  ],
                ),
              ),
            ),
          if (fixtures.isNotEmpty && !loading) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${fixtures.length} fixtures',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (selectedIds.length == fixtures.length) {
                        selectedIds.clear();
                      } else {
                        selectedIds
                          ..clear()
                          ..addAll(
                            fixtures.map((e) => e['fixture_id'] as int),
                          );
                      }
                    });
                  },
                  child: Text(
                    selectedIds.length == fixtures.length
                        ? 'CLEAR'
                        : 'SELECT ALL',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...fixtures.map((f) {
              final id = f['fixture_id'] as int;
              final checked = selectedIds.contains(id);
              final kickoff = DateTime.parse(
                f['kickoff_at'].toString(),
              ).toLocal();

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: checked
                          ? colors.primary
                          : colors.outlineVariant.withValues(alpha: .5),
                      width: checked ? 1.5 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => toggleFixture(id),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        children: [
                          Checkbox(
                            value: checked,
                            onChanged: (_) => toggleFixture(id),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f['league_name'].toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${f['home_name']}  vs  ${f['away_name']}',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${DateFormat('dd MMM • HH:mm').format(kickoff)}'
                                  '${f['status_short'] == null ? '' : ' • ${f['status_short']}'}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              _TeamLogo(url: f['home_logo']?.toString()),
                              const SizedBox(height: 5),
                              _TeamLogo(url: f['away_logo']?.toString()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: Icon(Icons.shield_outlined, size: 20),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.shield_outlined, size: 20),
        ),
      ),
    );
  }
}
