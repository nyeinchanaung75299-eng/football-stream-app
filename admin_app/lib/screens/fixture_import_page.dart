import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'live_links_page.dart';
import 'soco_import_page.dart';
import '../analytics_service.dart';
import '../services/function_gateway.dart';

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
      final data = await FunctionGateway.invoke(
        'football-fixtures',
        body: {
          'mode': mode,
          'date': DateFormat('yyyy-MM-dd').format(selectedDate),
        },
      );
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

      await AnalyticsService.capture(
        'fixture list loaded',
        properties: {
          'mode': mode,
          'fixture_count': rows.length,
        },
      );
      if (!mounted) return;
      setState(() {
        fixtures = rows
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      await AnalyticsService.capture(
        'fixture list failed',
        properties: {'mode': mode},
      );
      if (!mounted) return;
      setState(() {
        fixtures = [];
        final raw = e.toString();
        final lower = raw.toLowerCase();
        if (lower.contains('football_providers_missing') ||
            lower.contains('no football fixture provider is configured')) {
          errorText =
              'No fixture API is configured. Add API_FOOTBALL_KEY and/or FOOTBALL_DATA_ORG_KEY in Supabase Edge Functions > Secrets.';
        } else if (lower.contains('account is suspended') &&
            !lower.contains('football_data_org')) {
          errorText =
              'API-Football is suspended. Add FOOTBALL_DATA_ORG_KEY to use football-data.org as the automatic backup.';
        } else {
          errorText =
              'Could not load fixtures: ${raw.replaceFirst('Exception: ', '')}';
        }
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
      final savedIds = <String>[];

      var skippedDeleted = 0;
      for (final f in chosen) {
        final fixtureId = f['fixture_id'];
        final existing = await Supabase.instance.client
            .from('matches')
            .select('id,deleted_at')
            .eq('external_fixture_id', fixtureId)
            .maybeSingle();

        if (existing != null && existing['deleted_at'] != null) {
          skippedDeleted += 1;
          continue;
        }

        final saved = await Supabase.instance.client
            .from('matches')
            .upsert(
              {
                'external_fixture_id': f['fixture_id'],
                'source': (f['provider'] ?? 'api_football').toString(),
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
            )
            .select('id')
            .single();

        savedIds.add(saved['id'].toString());
      }

      await AnalyticsService.capture(
        'matches published',
        properties: {
          'requested_count': chosen.length,
          'published_count': savedIds.length,
          'skipped_deleted': skippedDeleted,
        },
      );

      if (!mounted) return;

      setState(() => selectedIds.clear());

      if (skippedDeleted > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$skippedDeleted deleted match(es) were skipped and not restored.',
            ),
          ),
        );
      }

      if (chosen.length == 1 && savedIds.isNotEmpty) {
        final streamAction = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          showDragHandle: true,
          builder: (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 44),
                const SizedBox(height: 10),
                const Text(
                  'Match published',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pick a Soco / YYZB / Fawa source now, or add a stream manually.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'source'),
                    icon: const Icon(Icons.podcasts_rounded),
                    label: const Text('PICK SOCO / YYZB / FAWA'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, 'manual'),
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('ADD STREAM MANUALLY'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, 'done'),
                  child: const Text('DONE'),
                ),
              ],
            ),
          ),
        );

        if (streamAction == 'source' && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(
                name: '/admin/stream-source-picker',
              ),
              builder: (_) => SocoImportPage(
                initialMatchId: savedIds.first,
              ),
            ),
          );
        } else if (streamAction == 'manual' && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(
                name: '/admin/stream-servers',
              ),
              builder: (_) => LiveLinksPage(
                initialMatchId: savedIds.first,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${chosen.length} matches published. Open Soco / YYZB / Fawa Links or Stream Servers to add links.',
            ),
          ),
        );
      }
    } catch (e) {
      await AnalyticsService.capture(
        'match publish failed',
        properties: {'requested_count': chosen.length},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  String _providerLabel(dynamic value) {
    return value?.toString() == 'football_data_org'
        ? 'football-data.org'
        : 'API-Football';
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
                Expanded(
                  child: Text(
                    '${fixtures.length} fixtures • ${_providerLabel(fixtures.first['provider'])}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
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
