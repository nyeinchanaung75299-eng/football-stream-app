import 'package:flutter/material.dart';
import '../viewer_navigation.dart';
import '../widgets/tab_swipe_region.dart';
import 'home_page.dart';
import 'source_browser_page.dart';
import 'channels_page.dart';
import 'highlight_source_page.dart';

/// Mount pages lazily and retain their filter, scroll and loading state.
/// The native player and other pushed routes are outside this swipe region.
class ViewerTabsPage extends StatefulWidget {
  const ViewerTabsPage({super.key, this.backendReady, this.initialMatchId});
  final Future<void>? backendReady;
  final String? initialMatchId;
  @override
  State<ViewerTabsPage> createState() => _ViewerTabsPageState();
}
class _ViewerTabsPageState extends State<ViewerTabsPage> {
  int _index = 0;
  final Set<int> _visited = {0};
  void _select(int index) {
    if (index == _index || index < 0 || index >= viewerSourceTabs.length) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() { _visited.add(index); _index = index; });
  }
  Widget _page(int index) => switch (index) {
    0 => HomePage(backendReady: widget.backendReady, initialMatchId: widget.initialMatchId,
      active: _index == 0, onTabSelected: _select),
    6 => ChannelsPage(active: _index == 6, onTabSelected: _select),
    7 => HighlightsSourcePage(onTabSelected: _select),
    _ => SourceBrowserPage(source: viewerSourceAt(index), active: _index == index,
      onTabSelected: _select),
  };
  @override
  Widget build(BuildContext context) => TabSwipeRegion(
    index: _index, count: viewerSourceTabs.length, onSelected: _select,
    child: Stack(fit: StackFit.expand, children: [
      for (final index in (_visited.toList()..sort()))
        Offstage(key: ValueKey('viewer-tab-$index'), offstage: _index != index,
          child: TickerMode(enabled: _index == index,
            child: FocusScope(canRequestFocus: _index == index,
              descendantsAreFocusable: _index == index, child: _page(index)))),
    ]),
  );
}
