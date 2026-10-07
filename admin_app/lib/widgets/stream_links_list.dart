import 'package:flutter/material.dart';

class StreamLinksList extends StatelessWidget {
  const StreamLinksList({
    super.key,
    required this.future,
    required this.rowBuilder,
  });

  final Future<List<Map<String, dynamic>>> future;
  final Widget Function(Map<String, dynamic> row) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        // FutureBuilder retains the previous future's data while waiting.
        // Hide it so a match switch never leaves old Edit/Delete actions live.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Could not load servers. Tap refresh to try again.'),
            ),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('No servers added yet.'),
            ),
          );
        }
        return Column(children: rows.map(rowBuilder).toList());
      },
    );
  }
}
