import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import 'live_links_page.dart';

/// Compact admin management for every non-deleted live fixture.
///
/// This intentionally has no Upcoming / Live / All segment: this is the one
/// recovery screen where an administrator can always reach every saved match.
class EditLivePage extends StatefulWidget {
  const EditLivePage({super.key});

  @override
  State<EditLivePage> createState() => _EditLivePageState();
}

class _EditLivePageState extends State<EditLivePage> {
  late Future<List<Map<String, dynamic>>> _matchesFuture;

  @override
  void initState() {
    super.initState();
    _matchesFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,league,home_team,away_team,home_logo_url,away_logo_url,'
          'kickoff_at,sort_order,is_live,is_active,is_featured,publish_state,'
          'deleted_at',
        )
        .timeout(const Duration(seconds: 8));

    final rows = List<Map<String, dynamic>>.from(data)
        .where((row) => row['deleted_at'] == null)
        .toList();
    rows.sort((a, b) {
      final byTime = _kickoffOf(a).compareTo(_kickoffOf(b));
      if (byTime != 0) return byTime;
      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 0;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 0;
      final byOrder = aOrder.compareTo(bOrder);
      if (byOrder != 0) return byOrder;
      return '${a['home_team'] ?? ''}'
          .toLowerCase()
          .compareTo('${b['home_team'] ?? ''}'.toLowerCase());
    });
    return rows;
  }

  void _reload() {
    if (mounted) setState(() => _matchesFuture = _load());
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _deleteMatch(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete match?'),
        content: const Text(
          'This hides the match and permanently deletes all of its live links.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // A zero-row UPDATE can silently succeed when RLS blocks a write.
      // Require the updated row before claiming the match was deleted.
      final deleted = await Supabase.instance.client.from('matches').update({
        'is_active': false,
        'is_featured': false,
        'is_live': false,
        'publish_state': 'draft',
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id).select('id,is_active,is_featured,publish_state,deleted_at').single();

      if (deleted['deleted_at'] == null ||
          deleted['is_active'] != false ||
          deleted['is_featured'] != false ||
          deleted['publish_state'] != 'draft') {
        throw StateError('Match deletion was not saved. Please retry.');
      }

      await Supabase.instance.client
          .from('stream_links')
          .delete()
          .eq('match_id', id);
      await AnalyticsService.capture('match deleted', properties: {'match_id': id});
      _message('Match deleted.');
      _reload();
    } catch (error) {
      await AnalyticsService.capture(
        'match delete failed',
        properties: {'match_id': id},
      );
      _message('Delete failed: $error');
    }
  }

  Future<void> _deleteLinks(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete live links?'),
        content: const Text(
          'All live links for this match will be permanently deleted. The match itself stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE LINKS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('stream_links')
          .delete()
          .eq('match_id', id);
      await AnalyticsService.capture(
        'match live links deleted',
        properties: {'match_id': id},
      );
      _message('Live links deleted.');
    } catch (error) {
      _message('Could not delete live links: $error');
    }
  }

  Future<void> _editMatch(Map<String, dynamic> match) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditMatchPage(match: match)),
    );
    if (saved == true) {
      _message('Match updated.');
      _reload();
    }
  }

  void _openLinks(String matchId) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LiveLinksPage(initialMatchId: matchId)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Live Edit & Delete'),
          actions: [
            IconButton(
              tooltip: 'Refresh matches',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _matchesFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load matches. Check your connection and retry.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('RETRY'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) return const Center(child: Text('No matches yet.'));

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final match = rows[index];
                final id = match['id'].toString();
                return _LiveEditCard(
                  match: match,
                  onEditMatch: () => _editMatch(match),
                  onDeleteMatch: () => _deleteMatch(id),
                  onEditLinks: () => _openLinks(id),
                  onDeleteLinks: () => _deleteLinks(id),
                );
              },
            );
          },
        ),
      );
}

class _LiveEditCard extends StatelessWidget {
  const _LiveEditCard({
    required this.match,
    required this.onEditMatch,
    required this.onDeleteMatch,
    required this.onEditLinks,
    required this.onDeleteLinks,
  });

  final Map<String, dynamic> match;
  final VoidCallback onEditMatch;
  final VoidCallback onDeleteMatch;
  final VoidCallback onEditLinks;
  final VoidCallback onDeleteLinks;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kickoff = _kickoffOf(match).toLocal();
    final isLive = match['is_live'] == true;
    final home = '${match['home_team'] ?? 'Home'}';
    final away = '${match['away_team'] ?? 'Away'}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${match['league'] ?? 'Football'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Keep the scheduled status and edit actions centered above kickoff.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusPill(label: isLive ? 'LIVE' : 'SCHEDULED'),
                IconButton(
                  tooltip: 'Edit match',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEditMatch,
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: 'Delete match',
                  visualDensity: VisualDensity.compact,
                  color: colors.error,
                  onPressed: onDeleteMatch,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _TeamBlock(
                    name: home,
                    logo: '${match['home_logo_url'] ?? ''}',
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          DateFormat('h:mm a', 'en_US').format(kickoff),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMM', 'en_US').format(kickoff),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _TeamBlock(
                    name: away,
                    logo: '${match['away_logo_url'] ?? ''}',
                  ),
                ),
              ],
            ),
            const Divider(height: 17),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'L-LINKS',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: .4,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit live links',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEditLinks,
                  icon: const Icon(Icons.edit_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Delete all live links',
                  visualDensity: VisualDensity.compact,
                  color: colors.error,
                  onPressed: onDeleteLinks,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.name, required this.logo});

  final String name;
  final String logo;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _TeamLogo(url: logo),
          const SizedBox(height: 5),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      );
}

class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.shield_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: 38,
    );
    if (!url.startsWith('http')) {
      return SizedBox(width: 52, height: 52, child: Center(child: fallback));
    }
    return SizedBox(
      width: 52,
      height: 52,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Center(child: fallback),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final live = label == 'LIVE';
    final colors = Theme.of(context).colorScheme;
    final color = live ? colors.error : colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _EditMatchPage extends StatefulWidget {
  const _EditMatchPage({required this.match});

  final Map<String, dynamic> match;

  @override
  State<_EditMatchPage> createState() => _EditMatchPageState();
}

class _EditMatchPageState extends State<_EditMatchPage> {
  late final league = TextEditingController(text: '${widget.match['league'] ?? ''}');
  late final home = TextEditingController(text: '${widget.match['home_team'] ?? ''}');
  late final away = TextEditingController(text: '${widget.match['away_team'] ?? ''}');
  late final homeLogo = TextEditingController(text: '${widget.match['home_logo_url'] ?? ''}');
  late final awayLogo = TextEditingController(text: '${widget.match['away_logo_url'] ?? ''}');
  late final order = TextEditingController(text: '${widget.match['sort_order'] ?? 0}');
  late DateTime kickoff = _kickoffOf(widget.match).toLocal();
  late bool live = widget.match['is_live'] == true;
  late bool active = widget.match['is_active'] == true;
  late bool featured = widget.match['is_featured'] != false;
  late bool published = (widget.match['publish_state'] ?? 'published') == 'published';
  bool saving = false;

  @override
  void dispose() {
    for (final field in [league, home, away, homeLogo, awayLogo, order]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: kickoff,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (value != null && mounted) {
      setState(() {
        kickoff = DateTime(
          value.year,
          value.month,
          value.day,
          kickoff.hour,
          kickoff.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(kickoff),
    );
    if (value != null && mounted) {
      setState(() {
        kickoff = DateTime(
          kickoff.year,
          kickoff.month,
          kickoff.day,
          value.hour,
          value.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    if (saving) return;
    if (league.text.trim().isEmpty ||
        home.text.trim().isEmpty ||
        away.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League and team names cannot be empty.')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await Supabase.instance.client.from('matches').update({
        'league': league.text.trim(),
        'home_team': home.text.trim(),
        'away_team': away.text.trim(),
        'home_logo_url':
            homeLogo.text.trim().isEmpty ? null : homeLogo.text.trim(),
        'away_logo_url':
            awayLogo.text.trim().isEmpty ? null : awayLogo.text.trim(),
        'kickoff_at': kickoff.toUtc().toIso8601String(),
        'sort_order': int.tryParse(order.text) ?? 0,
        'is_featured': featured,
        'publish_state': published ? 'published' : 'draft',
        'is_live': live,
        'is_active': active,
      }).eq('id', widget.match['id']);
      await AnalyticsService.capture(
        'match updated',
        properties: {
          'match_id': widget.match['id'].toString(),
          'featured': featured,
          'published': published,
          'is_live': live,
          'is_active': active,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Match update failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _twoColumns(Widget left, Widget right) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 340) {
            return Column(
              children: [left, const SizedBox(height: 10), right],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 10),
              Expanded(child: right),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Live Edit')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Column(
              children: [
                TextField(
                  controller: league,
                  decoration: const InputDecoration(labelText: 'League'),
                ),
                const SizedBox(height: 10),
                _twoColumns(
                  TextField(
                    controller: home,
                    decoration: const InputDecoration(labelText: 'Home team'),
                  ),
                  TextField(
                    controller: away,
                    decoration: const InputDecoration(labelText: 'Away team'),
                  ),
                ),
                const SizedBox(height: 10),
                _twoColumns(
                  TextField(
                    controller: homeLogo,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Home logo URL'),
                  ),
                  TextField(
                    controller: awayLogo,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Away logo URL'),
                  ),
                ),
                const SizedBox(height: 10),
                _twoColumns(
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(DateFormat('dd MMM yyyy').format(kickoff)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(DateFormat('h:mm a', 'en_US').format(kickoff)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Display order'),
                ),
                const SizedBox(height: 8),
                _twoColumns(
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Featured'),
                    value: featured,
                    onChanged: (value) => setState(() => featured = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Published'),
                    value: published,
                    onChanged: (value) => setState(() => published = value),
                  ),
                ),
                _twoColumns(
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Live'),
                    value: live,
                    onChanged: (value) => setState(() => live = value),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: active,
                    onChanged: (value) => setState(() => active = value),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(saving ? 'SAVING…' : 'SAVE MATCH'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

DateTime _kickoffOf(Map<String, dynamic> match) =>
    DateTime.tryParse(match['kickoff_at']?.toString() ?? '')?.toLocal() ??
    DateTime.now();
