import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics_service.dart';
import '../services/function_gateway.dart';

class SocoImportPage extends StatefulWidget {
  const SocoImportPage({super.key, this.initialMatchId});

  final String? initialMatchId;

  @override
  State<SocoImportPage> createState() => _SocoImportPageState();
}

class _SocoImportPageState extends State<SocoImportPage> {
  String? targetMatchId;
  bool loading = false;
  bool availableOnly = true;
  String source = 'soco';
  String dayFilter = 'today';
  String? errorText;
  List<Map<String, dynamic>> sourceMatches = const [];

  @override
  void initState() {
    super.initState();
    targetMatchId = widget.initialMatchId;
    _loadSoco();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<List<Map<String, dynamic>>> _loadTargetMatches() async {
    final data = await Supabase.instance.client
        .from('matches')
        .select(
          'id,home_team,away_team,kickoff_at,sort_order,is_live,is_active,'
          'is_finished,is_featured,publish_state,deleted_at',
        )
        .eq('is_active', true)
        .order('kickoff_at', ascending: true)
        .order('sort_order', ascending: true)
        .order('home_team', ascending: true);

    final now = DateTime.now();
    const staleKickoffGrace = Duration(hours: 5);

    return List<Map<String, dynamic>>.from(data)
        .where((row) {
          final kickoff = DateTime.tryParse(
            row['kickoff_at']?.toString() ?? '',
          )?.toLocal();
          final stale = row['is_live'] != true &&
              kickoff != null &&
              now.difference(kickoff) > staleKickoffGrace;

          return row['deleted_at'] == null &&
              row['is_active'] == true &&
              row['is_finished'] != true &&
              row['is_featured'] != false &&
              (row['publish_state'] ?? 'published') == 'published' &&
              !stale;
        })
        .toList();
  }

  Future<void> _loadSoco() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final data = await FunctionGateway.invoke(
        'source-match-list',
        body: {
          'source': source,
        },
      );

      final rows = data is Map ? data['matches'] : null;
      if (rows is! List) {
        throw const FormatException('Source match list is invalid.');
      }

      final parsed = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      parsed.sort((a, b) {
        final at = DateTime.tryParse(a['match_time']?.toString() ?? '')
                ?.toLocal() ??
            DateTime(9999);
        final bt = DateTime.tryParse(b['match_time']?.toString() ?? '')
                ?.toLocal() ??
            DateTime(9999);
        final byTime = at.compareTo(bt);
        if (byTime != 0) return byTime;
        return (a['home_team'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['home_team'] ?? '').toString().toLowerCase(),
            );
      });

      await AnalyticsService.capture(
        'source match list loaded',
        properties: {
          'source': source,
          'match_count': parsed.length,
        },
      );
      if (!mounted) return;
      setState(() => sourceMatches = parsed);
    } catch (e) {
      await AnalyticsService.capture(
        'source match list failed',
        properties: {'source': source},
      );
      if (!mounted) return;
      final detail = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        sourceMatches = const [];
        errorText =
            'Could not load ${_sourceLabel(source)} sources. $detail';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _visibleSourceMatches {
    Iterable<Map<String, dynamic>> rows = sourceMatches;

    if (availableOnly) {
      rows = rows.where((row) {
        final anchors = row['anchors'];
        return anchors is List && anchors.isNotEmpty;
      });
    }

    if (source == 'fawa' || dayFilter == 'all') return rows.toList();

    final now = DateTime.now();
    final wanted = dayFilter == 'tomorrow'
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    return rows.where((row) {
      final time = DateTime.tryParse(
        row['match_time']?.toString() ?? '',
      )?.toLocal();
      return time != null && _sameDate(time, wanted);
    }).toList();
  }

  Future<String?> _chooseDestination() async {
    final loaded = await _loadTargetMatches();
    if (!mounted || loaded.isEmpty) return null;

    final targets = List<Map<String, dynamic>>.from(loaded);
    final suggestedId = targetMatchId;
    if (suggestedId != null) {
      targets.sort((a, b) {
        final aSuggested = a['id']?.toString() == suggestedId;
        final bSuggested = b['id']?.toString() == suggestedId;
        if (aSuggested == bSuggested) return 0;
        return aSuggested ? -1 : 1;
      });
    }

    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .9,
        minChildSize: .45,
        builder: (context, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose NCA match',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                itemCount: targets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final m = targets[index];
                  final kickoff = DateTime.tryParse(
                    m['kickoff_at']?.toString() ?? '',
                  )?.toLocal();
                  final when = kickoff == null
                      ? '--:--'
                      : DateFormat('dd MMM • HH:mm').format(kickoff);

                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    leading: const Icon(Icons.sports_soccer_rounded),
                    title: Text(
                      '${m['home_team']} vs ${m['away_team']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(when),
                    trailing: m['id']?.toString() == suggestedId
                        ? const Text(
                            'CURRENT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(
                      sheetContext,
                      m['id']?.toString(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAnchor(
    Map<String, dynamic> match,
    Map<String, dynamic> anchor,
  ) async {
    final room = anchor['room_num']?.toString().trim() ?? '';
    if (room.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final data = await FunctionGateway.invoke(
        'soco-links',
        body: {
          'action': 'streams',
          'source': source,
          'room_num': room,
          'schedule_id': match['schedule_id'],
          'page_url': anchor['page_url'] ?? match['page_url'],
        },
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      final rows = data is Map ? data['lines'] : null;
      if (rows is! List) {
        throw const FormatException('No stream quality list returned.');
      }

      final lines = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => (row['url'] ?? '').toString().trim().isNotEmpty)
          .toList();

      await AnalyticsService.capture(
        'source lines loaded',
        properties: {
          'source': source,
          'line_count': lines.length,
          'source_live':
              data is Map &&
              (data['live_status'] == true ||
                  data['live_status'] == 1 ||
                  data['live_status']?.toString() == '1'),
        },
      );

      if (!mounted) return;
      if (lines.isEmpty) {
        message('No playable line is available for this streamer.');
        return;
      }

      await _showQualityPicker(
        match: match,
        anchor: anchor,
        lines: lines,
        sourceLiveStatus: data is Map ? data['live_status'] : null,
      );
    } catch (e) {
      await AnalyticsService.capture(
        'source lines failed',
        properties: {'source': source},
      );
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      final detail = e.toString().replaceFirst('Exception: ', '');
      message(
        'Could not load ${_sourceLabel(source)} stream links. $detail',
      );
    }
  }

  Future<void> _showQualityPicker({
    required Map<String, dynamic> match,
    required Map<String, dynamic> anchor,
    required List<Map<String, dynamic>> lines,
    dynamic sourceLiveStatus,
  }) async {
    final anchorName =
        (anchor['nick_name'] ?? 'Streamer').toString().trim();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Stream Quality',
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${match['home_team']} vs ${match['away_team']} • $anchorName',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (sourceLiveStatus != null) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final live = sourceLiveStatus == true ||
                        sourceLiveStatus == 1 ||
                        sourceLiveStatus.toString() == '1';
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (live ? Colors.green : Colors.orange)
                              .withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          live ? 'SOURCE LIVE' : 'SOURCE NOT LIVE',
                          style: TextStyle(
                            color: live ? Colors.green : Colors.orange,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              ...lines.map((line) {
                final label = (line['label'] ?? 'Stream').toString();
                final type =
                    (line['stream_type'] ?? 'auto').toString().toUpperCase();
                final url = (line['url'] ?? '').toString();
                final referer = (line['referer'] ?? '').toString().trim();
                final origin = (line['origin'] ?? '').toString().trim();
                final health =
                    (line['health_status'] ?? '').toString().toLowerCase();

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          type == 'HLS'
                              ? Icons.play_circle_fill_rounded
                              : Icons.video_file_rounded,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (health.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: (health == 'healthy'
                                                ? Colors.green
                                                : health == 'failed' ||
                                                        health == 'dead'
                                                    ? Colors.red
                                                    : Colors.orange)
                                            .withValues(alpha: .12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        health.toUpperCase(),
                                        style: TextStyle(
                                          color: health == 'healthy'
                                              ? Colors.green
                                              : health == 'failed' ||
                                                      health == 'dead'
                                                  ? Colors.red
                                                  : Colors.orange,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (referer.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Referer: $referer',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (origin.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Origin: $origin',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy link',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: url),
                            );
                            await AnalyticsService.capture(
                              'source link copied',
                              properties: {
                                'source': source,
                                'stream_type':
                                    (line['stream_type'] ?? 'auto').toString(),
                              },
                            );
                            message('${_sourceLabel(source)} link copied.');
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        FilledButton(
                          onPressed: () async {
                            final added = await _addLine(
                              line: line,
                              anchorName: anchorName,
                            );
                            if (added && sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                          child: const Text('ADD'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  targetMatchId == null
                      ? 'Each ADD will ask which NCA match to use.'
                      : 'Each ADD will still ask for the NCA match. The selected destination is shown first.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _addLine({
    required Map<String, dynamic> line,
    required String anchorName,
  }) async {
    // Only reuse a destination when the admin explicitly selected one from
    // the destination dropdown (or this page was opened for a fixed match).
    // A match picked from the ADD dialog is intentionally one-shot so every
    // later ADD asks again instead of silently reusing the previous match.
    final presetTarget = targetMatchId;
    final target = await _chooseDestination();
    if (target == null) return false;

    final url = (line['url'] ?? '').toString().trim();
    if (url.isEmpty) return false;

    final existing = await Supabase.instance.client
        .from('stream_links')
        .select('id')
        .eq('match_id', target)
        .eq('stream_url', url)
        .maybeSingle();

    if (existing != null) {
      await AnalyticsService.capture(
        'source line duplicate',
        properties: {
          'source': source,
          'destination_preset': presetTarget != null,
        },
      );
      message('This source line is already added.');
      return false;
    }

    final sourceName = _sourceLabel(source);
    final label = (line['label'] ?? sourceName).toString();
    final type = (line['stream_type'] ?? 'auto').toString();
    final resolution = (line['resolution'] ?? label).toString();

    final inserted = await Supabase.instance.client
        .from('stream_links')
        .insert({
          'match_id': target,
          'label': '$sourceName • $anchorName • $label',
          'resolution': resolution,
          'stream_type': type,
          'stream_url': url,
          'referer': nullable(line['referer']?.toString()),
          'origin': nullable(line['origin']?.toString()),
          'use_webview': false,
          'webview_url': null,
          'send_notification': false,
          'is_active': true,
          'expires_at': line['expires_at'],
        })
        .select('id')
        .single();

    var resultText = 'saved';
    try {
      final checked = await FunctionGateway.invoke(
        'stream-health',
        body: {'link_id': inserted['id']},
      );
      if (checked is Map && checked['health_status'] != null) {
        resultText = checked['health_status'].toString();
      }
    } catch (_) {
      resultText = 'health pending';
    }

    await AnalyticsService.capture(
      'source line imported',
      properties: {
        'source': source,
        'stream_type': type,
        'resolution': resolution,
        'destination_preset': presetTarget != null,
        'health_status': resultText,
      },
    );

    message('$sourceName $label added • $resultText');
    return true;
  }

  String? nullable(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _sourceLabel(String value) {
    switch (value) {
      case 'yyzb':
        return 'YYZB';
      case 'fawa':
        return 'Fawa';
      default:
        return 'Soco';
    }
  }

  Widget _sourceButton(String value, String label) {
    final selected = source == value;
    final onPressed = loading
        ? null
        : () {
            setState(() {
              source = value;
              dayFilter = value == 'fawa' ? 'all' : 'today';
              sourceMatches = const [];
              errorText = null;
            });
            AnalyticsService.capture(
              'source provider selected',
              properties: {'source': value},
            );
            _loadSoco();
          };

    return selected
        ? FilledButton.tonal(
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onPressed,
            child: Text(label),
          );
  }

  Widget _dayButton(String value, String label) {
    final selected = dayFilter == value;
    return selected
        ? FilledButton.tonal(
            onPressed: () => setState(() => dayFilter = value),
            child: Text(label),
          )
        : TextButton(
            onPressed: () => setState(() => dayFilter = value),
            child: Text(label),
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = _visibleSourceMatches;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Source Picker'),
        actions: [
          IconButton(
            tooltip: 'Refresh source',
            onPressed: loading ? null : _loadSoco,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadTargetMatches(),
        builder: (context, targetSnapshot) {
          final targets =
              targetSnapshot.data ?? const <Map<String, dynamic>>[];

          if (targetMatchId != null &&
              !targets.any((row) => row['id'] == targetMatchId)) {
            targetMatchId = null;
          }

          return RefreshIndicator(
            onRefresh: _loadSoco,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: DropdownButtonFormField<String>(
                      value: targetMatchId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Destination match (optional)',
                        prefixIcon: Icon(Icons.sports_soccer_rounded),
                      ),
                      items: targets.map((m) {
                        final kickoff = DateTime.tryParse(
                          m['kickoff_at']?.toString() ?? '',
                        )?.toLocal();
                        final when = kickoff == null
                            ? '--:--'
                            : DateFormat('dd MMM • HH:mm').format(kickoff);
                        return DropdownMenuItem(
                          value: m['id'] as String,
                          child: Text(
                            '$when · ${m['home_team']} vs ${m['away_team']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => targetMatchId = value),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sourceButton('soco', 'Soco'),
                    _sourceButton('yyzb', 'YYZB'),
                    _sourceButton('fawa', 'Fawa'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Source: ${_sourceLabel(source)}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SwitchListTile.adaptive(
                  value: availableOnly,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Available only',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'Hide matches that have no source yet.',
                  ),
                  onChanged: (value) =>
                      setState(() => availableOnly = value),
                ),
                const SizedBox(height: 4),
                if (source != 'fawa')
                  Row(
                    children: [
                      _dayButton('today', 'Today'),
                    const SizedBox(width: 4),
                    _dayButton('tomorrow', 'Tomorrow'),
                    const SizedBox(width: 4),
                    _dayButton('all', 'All'),
                    const Spacer(),
                      if (loading)
                        const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  )
                else if (loading)
                  const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                const SizedBox(height: 8),
                if (errorText != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        errorText!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ),
                if (!loading && visible.isEmpty && errorText == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No football matches in this source section.'),
                    ),
                  ),
                ...visible.map((match) {
                  final kickoff = DateTime.tryParse(
                    match['match_time']?.toString() ?? '',
                  )?.toLocal();
                  final anchors = List<Map<String, dynamic>>.from(
                    match['anchors'] ?? const [],
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (match['league'] ?? 'Football').toString(),
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (match['hot'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'HOT',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${match['home_team']} vs ${match['away_team']}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            kickoff == null
                                ? 'Unknown time'
                                : DateFormat('dd MMM • HH:mm').format(kickoff),
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (anchors.isEmpty)
                            Text(
                              'No streamer is listed yet.',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: anchors.map((anchor) {
                                final name =
                                    (anchor['nick_name'] ?? 'Streamer')
                                        .toString();
                                return OutlinedButton.icon(
                                  onPressed: () =>
                                      _openAnchor(match, anchor),
                                  icon: const Icon(
                                    Icons.podcasts_rounded,
                                    size: 17,
                                  ),
                                  label: Text(name),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
