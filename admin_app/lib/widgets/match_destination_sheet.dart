import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../source_match_search.dart';

class MatchDestinationSheet extends StatefulWidget {
  const MatchDestinationSheet({super.key, required this.matches});
  final List<Map<String, dynamic>> matches;
  @override
  State<MatchDestinationSheet> createState() => _MatchDestinationSheetState();
}

class _MatchDestinationSheetState extends State<MatchDestinationSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.matches.where((row) => sourceMatchMatchesQuery(row, query)).toList();
    return DraggableScrollableSheet(
      expand: false, initialChildSize: .72, minChildSize: .4, maxChildSize: .9,
      builder: (context, controller) => Column(children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('Choose NCA match',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: TextField(
          decoration: const InputDecoration(isDense: true, hintText: 'Search teams or leagues', prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() => query = value),
        )),
        Expanded(child: matches.isEmpty ? const Center(child: Text('No matching NCA matches.')) : ListView.builder(
          controller: controller, itemCount: matches.length,
          itemBuilder: (context, index) {
            final match = matches[index];
            final time = DateTime.tryParse(match['kickoff_at']?.toString() ?? '')?.toLocal();
            return ListTile(
              leading: const Icon(Icons.sports_soccer),
              title: Text('${match['home_team']} vs ${match['away_team']}'),
              subtitle: Text('${match['league'] ?? ''}${time == null ? '' : ' • ${DateFormat('dd MMM, h:mm a').format(time)}'}'),
              onTap: () => Navigator.pop(context, match['id'].toString()),
            );
          },
        )),
      ]),
    );
  }
}
