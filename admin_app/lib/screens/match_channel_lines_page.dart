import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../football_english.dart';
import '../services/channel_source_service.dart';
import 'channel_source_picker_page.dart';

/// Adds an existing, authorized TV channel line to one match.
///
/// This deliberately uses the Admin channel catalog only. It does not load
/// source-picker providers or accept third-party page links in this flow.
class MatchChannelLinesPage extends StatefulWidget {
  const MatchChannelLinesPage({super.key, required this.match});

  final Map<String, dynamic> match;

  @override
  State<MatchChannelLinesPage> createState() => _MatchChannelLinesPageState();
}

class _MatchChannelLinesPageState extends State<MatchChannelLinesPage> {
  late Future<List<Map<String, dynamic>>> _lines = _load();
  bool _adding = false;
  bool _syncingGuide = false;
  String? _lastGuideSummary;
  String? _removingId;

  String get _matchId => widget.match['id'].toString();

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  void _reload() => setState(() => _lines = _load());

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('stream_links')
        .select(
          'id,label,resolution,stream_type,is_active,health_status,sort_order,'
          'channel_id,channel_line_id',
        )
        .eq('match_id', _matchId)
        .order('sort_order')
        .order('created_at')
        .timeout(const Duration(seconds: 10));

    return List<Map<String, dynamic>>.from(rows)
        .where((row) =>
            row['channel_id'] != null && row['channel_line_id'] != null)
        .toList(growable: false);
  }

  Future<void> _chooseAndAdd() async {
    if (_adding) return;
    final selection = await Navigator.of(context).push<ChannelStreamSelection>(
      MaterialPageRoute(builder: (_) => const ChannelSourcePickerPage()),
    );
    if (selection == null || !mounted) return;
    if (selection.channelLineId == null) {
      _message('This channel line is incomplete. Refresh Channels and retry.');
      return;
    }
    if (selection.keyId.isNotEmpty || selection.keyData.isNotEmpty) {
      _message(
        'Protected channel lines cannot be added here. Choose an authorized direct channel line.',
      );
      return;
    }
    final channelLineId = selection.channelLineId!;

    setState(() => _adding = true);
    try {
      final client = Supabase.instance.client;
      final duplicate = await client
          .from('stream_links')
          .select('id')
          .eq('match_id', _matchId)
          .eq('channel_line_id', channelLineId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (duplicate != null) {
        _message('${selection.displayLabel} is already on this match.');
        return;
      }

      final rows = await client
          .from('stream_links')
          .select('sort_order')
          .eq('match_id', _matchId)
          .timeout(const Duration(seconds: 10));
      final nextOrder = List<Map<String, dynamic>>.from(rows).fold<int>(
            -1,
            (highest, row) =>
                ((row['sort_order'] as num?)?.toInt() ?? 0) > highest
                    ? ((row['sort_order'] as num?)?.toInt() ?? 0)
                    : highest,
          ) +
          1;

      await client.from('stream_links').insert({
        'match_id': _matchId,
        'channel_id': selection.channelId,
        'channel_line_id': channelLineId,
        'label': selection.displayLabel,
        'resolution': selection.lineLabel,
        'stream_type': selection.streamType,
        'stream_url': selection.streamUrl,
        'referer': selection.referer.isEmpty ? null : selection.referer,
        'origin': selection.origin.isEmpty ? null : selection.origin,
        // This match-attachment flow accepts only keyless direct channel
        // lines; protected channel catalog entries remain untouched.
        'key_id': null,
        'key_data': null,
        'use_webview': false,
        'send_notification': false,
        'is_active': true,
        'sort_order': nextOrder,
      }).timeout(const Duration(seconds: 12));

      _message('${selection.displayLabel} added to this match.');
      _reload();
    } on TimeoutException {
      _message('Could not confirm the save. Refresh before trying again.');
      _reload();
    } catch (_) {
      _message('Could not add this TV channel line. Please retry.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  // Uses server-side EPG matching. No player URL or DRM key crosses the UI.
  Future<void> _syncGuide() async {
    if (_syncingGuide) return;
    setState(() => _syncingGuide = true);
    try {
      final result = await Supabase.instance.client.functions
          .invoke('auto-match-channels', body: {'match_id': _matchId})
          .timeout(const Duration(seconds: 65));
      if (result.status < 200 || result.status >= 300) {
        _message('TV schedule sync unavailable. Existing match lines are unchanged.');
        return;
      }
      final payload = result.data;
      if (payload is! Map || payload['ok'] != true) {
        _message('TV schedule could not be verified. Refresh and retry.');
        return;
      }
      final mapped = (payload['mapped'] as num?)?.toInt() ?? 0;
      final attached = (payload['addedLines'] as num?)?.toInt() ?? 0;
      final protected = (payload['skippedProtected'] as num?)?.toInt() ?? 0;
      final message = 'EPG matched $mapped channel(s), added $attached direct line(s). '
          '$protected channel(s) have no eligible keyless direct line.';
      if (mounted) setState(() => _lastGuideSummary = message);
      _message(message);
      _reload();
    } on TimeoutException {
      _message('TV guide sync timed out. Refresh to check for saved results.');
      _reload();
    } catch (_) {
      _message('TV schedule sync failed. No existing lines were removed.');
      _reload();
    } finally {
      if (mounted) setState(() => _syncingGuide = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> line) async {
    if (_removingId != null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove TV channel line?'),
        content: const Text(
          'This removes the line from this match only. The channel catalog is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    final id = line['id'].toString();
    setState(() => _removingId = id);
    try {
      await Supabase.instance.client
          .from('stream_links')
          .delete()
          .eq('id', id)
          .timeout(const Duration(seconds: 10));
      _message('TV channel line removed from this match.');
      _reload();
    } catch (_) {
      _message('Could not remove this TV channel line. Please retry.');
    } finally {
      if (mounted) setState(() => _removingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kickoff = DateTime.tryParse(
      widget.match['kickoff_at']?.toString() ?? '',
    )?.toLocal();
    final home = englishKnownFootballName(
      widget.match['home_team']?.toString() ?? 'Home',
    );
    final away = englishKnownFootballName(
      widget.match['away_team']?.toString() ?? 'Away',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('TV Channel Lines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _chooseAndAdd,
        icon: _adding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_link_rounded),
        label: Text(_adding ? 'ADDING…' : 'ADD TV CHANNEL LINE'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _lines,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Could not load TV channel lines. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final lines = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        englishKnownFootballName(
                          widget.match['league']?.toString() ?? 'Football',
                          kind: 'league',
                        ),
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$home vs $away',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        kickoff == null
                            ? 'Kickoff time unavailable'
                            : DateFormat('EEE, d MMM • h:mm a', 'en_US')
                                .format(kickoff),
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📺 AUTO USE CHANNELS • TV SCHEDULE',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 7),
                      const Text(
                        'Checks confirmed football EPG (both teams + kickoff time). '
                        'Direct keyless channel lines are attached automatically. '
                        'Protected channel lines stay in the Channels catalog; '
                        'your manually attached match lines are preserved.',
                      ),
                      if (_lastGuideSummary != null) ...[
                        const SizedBox(height: 9),
                        Text(_lastGuideSummary!),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _syncingGuide ? null : _syncGuide,
                        icon: _syncingGuide
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.auto_awesome_rounded),
                        label: Text(_syncingGuide ? 'SYNCING TV GUIDE…' :
                            'SYNC MATCH CHANNELS NOW'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'TV CHANNEL LINES',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 8),
              if (lines.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'No TV channel line is attached yet. Use ADD TV CHANNEL LINE to choose one from Channels.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
              ...lines.map((line) {
                final active = line['is_active'] == true;
                final name = line['label']?.toString().trim();
                final detail = line['resolution']?.toString().trim();
                final removing = _removingId == line['id']?.toString();
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.tv_rounded,
                      color: active ? colors.primary : colors.outline,
                    ),
                    title: Text(
                      name == null || name.isEmpty ? 'TV channel' : name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      [
                        if (detail != null && detail.isNotEmpty) detail,
                        (line['stream_type']?.toString() ?? 'auto')
                            .toUpperCase(),
                        active ? 'ACTIVE' : 'DISABLED',
                      ].join(' • '),
                    ),
                    trailing: removing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            tooltip: 'Remove from match',
                            onPressed: () => _remove(line),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Text(
                'Only direct, keyless lines already saved under Channels can be attached here.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
