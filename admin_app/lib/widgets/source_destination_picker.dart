import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SourceDestinationPicker extends StatelessWidget {
  const SourceDestinationPicker({
    super.key,
    required this.future,
    required this.selectedId,
    required this.onChanged,
  });

  final Future<List<Map<String, dynamic>>> future;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final targets = snapshot.data ?? const <Map<String, dynamic>>[];
        final loading = snapshot.connectionState != ConnectionState.done;
        // The preset belongs to the page's state. An empty loading snapshot
        // must not clear it or pass a value absent from the dropdown items.
        final displayedId = targets.any((row) => row['id'] == selectedId)
            ? selectedId
            : null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: DropdownButtonFormField<String>(
              // Recreate the form field when loaded options change so its
              // internal selection picks up the previously hidden preset.
              key: ValueKey('${loading ? 'loading' : 'loaded'}:$displayedId'),
              value: displayedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: loading
                    ? 'Loading destinations...'
                    : 'Suggested destination (ADD confirms)',
                prefixIcon: const Icon(Icons.sports_soccer_rounded),
                errorText:
                    snapshot.hasError ? 'Could not load destinations.' : null,
              ),
              items: targets.map((match) {
                final kickoff = DateTime.tryParse(
                  match['kickoff_at']?.toString() ?? '',
                )?.toLocal();
                final when = kickoff == null
                    ? '--:--'
                    : DateFormat('dd MMM • HH:mm').format(kickoff);
                return DropdownMenuItem(
                  value: match['id'] as String,
                  child: Text(
                    '$when · ${match['home_team']} vs ${match['away_team']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: loading || snapshot.hasError ? null : onChanged,
            ),
          ),
        );
      },
    );
  }
}
