import 'package:flutter/material.dart';

import '../analytics_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'soco_import_page.dart';
import 'live_links_page.dart';
import '../services/admin_web_source_cache.dart';
import 'highlights_page.dart';
import 'stream_detector_page.dart'
    if (dart.library.html) 'stream_detector_page_web.dart';

/// Source selection lives in its own bottom navigation destination so source
/// providers do not crowd the live-management controls.
class StreamSourcePickerPage extends StatefulWidget {
  const StreamSourcePickerPage(
      {super.key, this.embedded = false, this.onSourceMutated});

  final bool embedded;

  /// Trigger guide invalidation only after a confirmed successful line save.
  final VoidCallback? onSourceMutated;

  @override
  State<StreamSourcePickerPage> createState() => _StreamSourcePickerPageState();
}

class _StreamSourcePickerPageState extends State<StreamSourcePickerPage> {
  @override
  void initState() {
    super.initState();
    try {
      AdminWebSourceCache.bindUser(
          Supabase.instance.client.auth.currentSession?.user.id);
    } catch (_) {}
  }

  static const _sources = <_SourceOption>[
    _SourceOption('soco', 'Soco', Icons.sports_soccer_rounded),
    _SourceOption('yyzb', 'YYZB', Icons.sensors_rounded),
    _SourceOption('cola', 'ColaTV', Icons.tv_rounded),
    _SourceOption('fawa', 'Fawa', Icons.live_tv_rounded),
    _SourceOption('arena', 'Arena Koora', Icons.stadium_rounded),
    _SourceOption('roxie', 'RoxieStreams', Icons.sports_soccer_rounded),
    _SourceOption('crichd', 'CricHD', Icons.sports_soccer_rounded),
    _SourceOption('highlights', 'Highlights', Icons.video_library_outlined),
  ];

  Future<void> _open(BuildContext context, _SourceOption source) async {
    AdminWebSourceCache.rememberSource(source.id);
    AnalyticsService.capture(
      'admin source provider opened',
      properties: {'source': source.id, 'entry': 'source_picker'},
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: RouteSettings(name: '/admin/stream-sources/${source.id}'),
        builder: (_) => source.id == 'highlights'
            ? const HighlightsPage()
            : SocoImportPage(
                initialSource: source.id, onMutated: widget.onSourceMutated),
      ),
    );
    if (mounted) setState(() {});
    // Source previews do not change data. Successful imports explicitly
    // invalidate dependent guides via onSourceMutated on every platform.
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 360 &&
              MediaQuery.textScalerOf(context).scale(16) < 24
          ? 2
          : 1;
      return CustomScrollView(
          key: const PageStorageKey('stream-source-picker'),
          slivers: [
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                sliver: SliverToBoxAdapter(
                    child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                      Text('Stream Sources',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900)),
                      TextButton.icon(
                          onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  settings: const RouteSettings(
                                      name: '/admin/stream-detector'),
                                  builder: (_) => const StreamDetectorPage())),
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('PLAYER URL')),
                    ]))),
            if (AdminWebSourceCache.recentSources.isNotEmpty ||
                AdminWebSourceCache.recentMatchId != null)
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final id in AdminWebSourceCache.recentSources)
                      for (final option in _sources.where((s) => s.id == id))
                        ActionChip(
                            label: Text('Recent • ${option.label}'),
                            onPressed: () => _open(context, option)),
                    if (AdminWebSourceCache.recentMatchId != null)
                      ActionChip(
                          label: const Text('Last imported match'),
                          onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                  builder: (_) => LiveLinksPage(
                                      initialMatchId:
                                          AdminWebSourceCache.recentMatchId)))),
                  ]))),
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 120,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final source = _sources[index];
                      return Card(
                          margin: EdgeInsets.zero,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                              onTap: () => _open(context, source),
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(source.icon,
                                            size: 30,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                        const SizedBox(height: 8),
                                        Text(source.label,
                                            maxLines: 2,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                      ]))));
                    }, childCount: _sources.length))),
          ]);
    });

    if (widget.embedded) return content;
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
