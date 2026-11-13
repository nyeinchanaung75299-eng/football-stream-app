import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/repository_logo.dart';

/// Reviews the full fixture before publishing. Missing time requires an
/// operator choice; it is never silently replaced with the current clock.
class RepositoryMatchImportSheet extends StatefulWidget {
  const RepositoryMatchImportSheet({super.key, required this.entry});
  final Map<String, dynamic> entry;
  @override
  State<RepositoryMatchImportSheet> createState() =>
      _RepositoryMatchImportSheetState();
}

class _RepositoryMatchImportSheetState
    extends State<RepositoryMatchImportSheet> {
  static const mmt = Duration(hours: 6, minutes: 30);
  late final meta =
      Map<String, dynamic>.from(widget.entry['event_meta'] as Map? ?? {});
  late DateTime? kickoff =
      DateTime.tryParse(meta['kickoff_at']?.toString() ?? '')?.toUtc();

  Future<void> chooseTime() async {
    final now = DateTime.now().toUtc().add(mmt);
    final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(2000),
        lastDate: DateTime(2099, 12, 31));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: now.hour, minute: now.minute),
        helpText: 'KICKOFF TIME — MMT');
    if (time == null || !mounted) return;
    setState(() => kickoff =
        DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
            .subtract(mmt));
  }

  Widget team(String side) {
    final logo = (meta['${side}_logo_url'] ?? '').toString();
    return Expanded(
        child: Column(children: [
      SizedBox(
          width: 48,
          height: 48,
          child: logo.isEmpty
              ? const Icon(Icons.shield_outlined, size: 36)
              : Image.network(repositoryLogoUrl(logo),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.shield_outlined, size: 36))),
      const SizedBox(height: 6),
      Text((meta['${side}_team'] ?? '').toString(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold)),
    ]));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Add match to Live',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text((meta['league'] ?? 'Football').toString()),
            const SizedBox(height: 14),
            Row(children: [
              team('home'),
              const Padding(padding: EdgeInsets.all(12), child: Text('VS')),
              team('away')
            ]),
            const SizedBox(height: 14),
            if (kickoff != null)
              Text(
                  '${DateFormat('dd MMM yyyy · h:mm a', 'en_US').format(kickoff!.add(mmt))} MMT'),
            if (meta['kickoff_at'] == null ||
                meta['kickoff_at'].toString().isEmpty)
              OutlinedButton.icon(
                  onPressed: chooseTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(kickoff == null
                      ? 'SET KICKOFF (MMT)'
                      : 'CHANGE KICKOFF (MMT)')),
            const SizedBox(height: 12),
            Text(
                '${widget.entry['stream_count'] ?? 0} source lines. '
                'Adds the teams, logos, kickoff and available lines to Live. '
                'Lines missing required DRM data are skipped.',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('You can edit the match and its lines in Controls.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: kickoff == null
                        ? null
                        : () => Navigator.pop(context, kickoff),
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('ADD MATCH + LINES'))),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL')),
          ]),
        ),
      ));
}
