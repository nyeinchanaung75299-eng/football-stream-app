import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tv_schedule_service.dart';

/// An operator's observation is evidence to review, not a reason to
/// automatically change a regional EPG binding or auto-attach a stream.
class EpgDiscrepanciesPage extends StatefulWidget {
  const EpgDiscrepanciesPage({super.key, this.initialChannelId});
  final String? initialChannelId;

  @override
  State<EpgDiscrepanciesPage> createState() => _EpgDiscrepanciesPageState();
}

class _EpgDiscrepanciesPageState extends State<EpgDiscrepanciesPage> {
  final _observed = TextEditingController();
  final _notes = TextEditingController();
  late Future<List<Map<String, dynamic>>> _channels;
  late Future<List<Map<String, dynamic>>> _reports;
  List<Map<String, dynamic>> _availableChannels = const [];
  DateTime _observedAt = DateTime.now();
  String? _channelId;
  bool _saving = false;
  String? _reviewingId;

  @override
  void initState() {
    super.initState();
    _channelId = widget.initialChannelId;
    _channels = _loadChannels();
    _reports = _loadReports();
  }

  Future<List<Map<String, dynamic>>> _loadChannels() async {
    final rows = await Supabase.instance.client.from('channels')
        .select('id,name,epg_id,epg_source')
        .order('name').limit(1000);
    _availableChannels = List<Map<String, dynamic>>.from(rows);
    return _availableChannels;
  }

  Future<List<Map<String, dynamic>>> _loadReports() async {
    final rows = await Supabase.instance.client
        .from('channel_epg_discrepancies')
        .select(
          'id,channel_id,observed_programme,observed_at,'
          'reported_epg_id,reported_epg_source,notes,status,'
          'guide_checked_at,guide_programme_at_check,created_at,'
          'channels(name)',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  void _refresh() {
    setState(() {
      _channels = _loadChannels();
      _reports = _loadReports();
    });
  }

  @override
  void dispose() {
    _observed.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _localTime(DateTime time) =>
      time.toLocal().toString().split('.').first;

  Future<void> _pickObservedTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _observedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_observedAt),
    );
    if (time == null || !mounted) return;
    setState(() => _observedAt = DateTime(
      date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _saveReport() async {
    final programme = _observed.text.trim();
    if (_saving || _channelId == null || programme.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select a channel and enter the programme you see.'),
      ));
      return;
    }
    Map<String, dynamic>? channel;
    for (final row in _availableChannels) {
      if (row['id'] == _channelId) { channel = row; break; }
    }
    if (channel == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('channel_epg_discrepancies').insert({
        'channel_id': _channelId,
        'observed_programme': programme,
        'observed_at': _observedAt.toUtc().toIso8601String(),
        'reported_epg_id': channel['epg_id'],
        'reported_epg_source': channel['epg_source'],
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      _observed.clear();
      _notes.clear();
      setState(() {
        _observedAt = DateTime.now();
        _reports = _loadReports();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('EPG mismatch saved for guide review. Mapping unchanged.'),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save the EPG report. Check admin access.'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _recheckGuide(Map<String, dynamic> report) async {
    final id = report['id']?.toString() ?? '';
    if (id.isEmpty || _reviewingId != null) return;
    setState(() => _reviewingId = id);
    try {
      // Refresh the canonical guide, not a stale cached response.
      final guide = await TvScheduleService().load(refresh: true);
      final channelId = report['channel_id']?.toString();
      TvScheduleChannel? channel;
      for (final entry in guide.channels) {
        if (entry.id == channelId) { channel = entry; break; }
      }
      final seenAt = DateTime.tryParse(
        report['observed_at']?.toString() ?? '')?.toUtc();
      TvScheduleProgramme? onAir;
      if (channel != null && seenAt != null) {
        for (final programme in channel.programmes) {
          final end = programme.end ??
              programme.start.add(const Duration(hours: 3));
          if (!programme.start.isAfter(seenAt) && end.isAfter(seenAt)) {
            onAir = programme;
            break;
          }
        }
      }
      if (!mounted) return;
      await Supabase.instance.client.from('channel_epg_discrepancies')
          .update({
            'guide_checked_at': DateTime.now().toUtc().toIso8601String(),
            'guide_programme_at_check': onAir?.title,
          })
          .eq('id', id);
      if (!mounted) return;
      setState(() => _reports = _loadReports());
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Guide recheck'),
          content: Text(
            'Observed: ${report['observed_programme']}\n'
            'At (device time): ${seenAt == null ? '?' : _localTime(seenAt)}\n\n'
            'Saved EPG: ${report['reported_epg_id'] ?? 'not linked'} '
            '(${report['reported_epg_source'] ?? '?'})\n'
            'Current EPG: ${channel?.epgId.isNotEmpty == true ? channel!.epgId : 'not linked'}\n\n'
            '${onAir == null
                ? 'No programme covering the observed time is available in the '
                  'current guide. This does not prove the feed is wrong.'
                : 'Guide at observed time: ${onAir.title}\n'
                  'Guide start (device time): ${_localTime(onAir.start)}'}\n\n'
            'The channel EPG mapping was not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('EPG guide recheck failed. Report remains saved.'),
      ));
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  Future<void> _setResolved(Map<String, dynamic> report) async {
    final id = report['id']?.toString() ?? '';
    if (id.isEmpty || _reviewingId != null) return;
    final wasResolved = report['status'] == 'resolved';
    setState(() => _reviewingId = id);
    try {
      await Supabase.instance.client.from('channel_epg_discrepancies')
          .update({
            'status': wasResolved ? 'open' : 'resolved',
            'resolved_at': wasResolved
                ? null : DateTime.now().toUtc().toIso8601String(),
          }).eq('id', id);
      if (mounted) setState(() => _reports = _loadReports());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not update EPG report status.'),
      ));
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('EPG mismatch reports'),
      actions: [
        IconButton(
          tooltip: 'Refresh EPG reports',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'Record the channel, the programme actually on screen, and its '
          'time. Recheck the guide before changing an EPG mapping. '
          'A report never changes stream links or channel mappings.',
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _channels,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: _refresh,
                child: const Text('Could not load channels. Retry'),
              );
            }
            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }
            final rows = snapshot.data!;
            final selected = rows.any((c) => c['id'] == _channelId)
                ? _channelId : null;
            return DropdownButtonFormField<String>(
              initialValue: selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'NCA channel',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final channel in rows)
                  DropdownMenuItem(
                    value: channel['id'].toString(),
                    child: Text(
                      '${channel['name']} • '
                      '${(channel['epg_id'] ?? 'No EPG')}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _channelId = value),
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _observed,
          maxLength: 240,
          decoration: const InputDecoration(
            labelText: 'Actually showing (match / programme)',
            hintText: 'Fiorentina vs Juventus',
            border: OutlineInputBorder(),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _pickObservedTime,
          icon: const Icon(Icons.schedule_rounded),
          label: Text('Observed (device time): ${_localTime(_observedAt)}'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Logo, commentary language, or other clues',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _saveReport,
          icon: const Icon(Icons.report_problem_outlined),
          label: const Text('Save EPG mismatch'),
        ),
        const SizedBox(height: 20),
        Text('Saved reports',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _reports,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: _refresh,
                child: const Text('Could not load reports. Retry'),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return const ListTile(title: Text('No EPG mismatch reports yet'));
            }
            return Column(
              children: [
                for (final report in snapshot.data!)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (report['channels'] is Map
                                ? (report['channels'] as Map)['name']
                                : null)?.toString() ?? 'Channel',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800),
                          ),
                          Text('On screen: ${report['observed_programme']}'),
                          Text('Observed: ${_localTime(
                            DateTime.tryParse(report['observed_at']?.toString() ?? '') ??
                              DateTime.now())} (device time)'),
                          Text('EPG: ${report['reported_epg_id'] ?? 'none'}'
                              ' / ${report['reported_epg_source'] ?? 'none'}'),
                          if ((report['notes'] ?? '').toString().isNotEmpty)
                            Text('Notes: ${report['notes']}'),
                          if (report['guide_checked_at'] != null)
                            Text('Last checked: ${_localTime(
                              DateTime.parse(report['guide_checked_at'].toString()))} '
                              '• Guide: ${report['guide_programme_at_check'] ?? 'not available'}'),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: _reviewingId == null
                                    ? () => _recheckGuide(report) : null,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Recheck guide'),
                              ),
                              TextButton(
                                onPressed: _reviewingId == null
                                    ? () => _setResolved(report) : null,
                                child: Text(report['status'] == 'resolved'
                                    ? 'Reopen' : 'Mark resolved'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
