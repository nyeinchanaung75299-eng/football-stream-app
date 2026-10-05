import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          'id,home_team,away_team,kickoff_at,sort_order,is_active,'
          'is_finished,is_featured,publish_state,deleted_at',
        )
        .eq('is_active', true)
        .order('kickoff_at', ascending: true)
        .order('sort_order', ascending: true)
        .order('home_team', ascending: true);

    return List<Map<String, dynamic>>.from(data)
        .where(
          (row) =>
              row['deleted_at'] == null &&
              row['is_finished'] != true &&
              row['is_featured'] != false &&
              (row['publish_state'] ?? 'published') == 'published',
        )
        .toList();
  }

  Future<void> _loadSoco() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final data = await FunctionGateway.invoke(
        'soco-links',
        body: {
          'action': 'matches',
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

      if (!mounted) return;
      setState(() => sourceMatches = parsed);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        sourceMatches = const [];
        errorText = 'Could not load ${_sourceLabel(source)} sources. Pull to retry.';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> get _visibleSourceMatches {
    if (source == 'fawa' || dayFilter == 'all') return sourceMatches;

    final now = DateTime.now();
    final wanted = dayFilter == 'tomorrow'
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);

    return sourceMatches.where((row) {
      final time = DateTime.tryParse(
        row['match_time']?.toString() ?? '',
      )?.toLocal();
      return time != null && _sameDate(time, wanted);
    }).toList();
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
          'page_url': match['page_url'],
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

      if (!mounted) return;
      if (lines.isEmpty) {
        message('No playable line is available for this streamer.');
        return;
      }

      await _showQualityPicker(
        match: match,
        anchor: anchor,
        lines: lines,
      );
    } catch (_) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      message('Could not load ${_sourceLabel(source)} stream links.');
    }
  }

  Future<void> _showQualityPicker({
    required Map<String, dynamic> match,
    required Map<String, dynamic> anchor,
    required List<Map<String, dynamic>> lines,
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
              const SizedBox(height: 12),
              ...lines.map((line) {
                final label = (line['label'] ?? 'Stream').toString();
                final type =
                    (line['stream_type'] ?? 'auto').toString().toUpperCase();
                final url = (line['url'] ?? '').toString();
                final referer = (line['referer'] ?? '').toString().trim();
                final origin = (line['origin'] ?? '').toString().trim();

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
                              Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
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
                            message('${_sourceLabel(source)} link copied.');
                          },
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        FilledButton(
                          onPressed: targetMatchId == null
                              ? null
                              : () async {
                                  await _addLine(
                                    line: line,
                                    anchorName: anchorName,
                                  );
                                  if (sheetContext.mounted) {
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
              if (targetMatchId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Choose a destination match at the top before adding a line.',
                    style: TextStyle(
                      color: colors.error,
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

  Future<void> _addLine({
    required Map<String, dynamic> line,
    required String anchorName,
  }) async {
    final target = targetMatchId;
    if (target == null) {
      message('Select a destination match first.');
      return;
    }

    final url = (line['url'] ?? '').toString().trim();
    if (url.isEmpty) return;

    final existing = await Supabase.instance.client
        .from('stream_links')
        .select('id')
        .eq('match_id', target)
        .eq('stream_url', url)
        .maybeSingle();

    if (existing != null) {
      message('This source line is already added.');
      return;
    }

    final sourceName = _sourceLabel(source);
    final label = (line['label'] ?? sourceName).toString();
    final type = (line['stream_type'] ?? 'auto').toString();
    final resolution = (line['resolution'] ?? label).toString();

    await Supabase.instance.client.from('stream_links').insert({
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
    });

    message('$sourceName $label added to the selected match.');
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
                        labelText: 'Add selected source line to',
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
                const SizedBox(height: 8),
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
