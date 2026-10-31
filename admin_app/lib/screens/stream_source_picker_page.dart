import 'package:flutter/material.dart';

import '../analytics_service.dart';
import 'soco_import_page.dart';

/// Source selection lives in its own bottom navigation destination so source
/// providers do not crowd the live-management controls.
class StreamSourcePickerPage extends StatelessWidget {
  const StreamSourcePickerPage({super.key, this.embedded = false});

  final bool embedded;

  static const _sources = <_SourceOption>[
    _SourceOption('soco', 'Soco', Icons.sports_soccer_rounded),
    _SourceOption('yyzb', 'YYZB', Icons.sensors_rounded),
    _SourceOption('fawa', 'Fawa', Icons.live_tv_rounded),
    _SourceOption('cola', 'ColaTV', Icons.tv_rounded),
  ];

  void _open(BuildContext context, _SourceOption source) {
    AnalyticsService.capture(
      'admin source provider opened',
      properties: {'source': source.id, 'entry': 'source_picker'},
    );
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/admin/stream-sources/${source.id}'),
        builder: (_) => SocoImportPage(initialSource: source.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: _sources.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Stream Sources',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                  ),
            ),
          );
        }
        final source = _sources[index - 1];
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(source.icon),
            title: Text(
              source.label,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _open(context, source),
          ),
        );
      },
    );

    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Stream Sources')),
      body: content,
    );
  }
}

class _SourceOption {
  const _SourceOption(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}
