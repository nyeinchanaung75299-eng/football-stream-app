import 'package:flutter/material.dart';

import '../playback_routes.dart';

String playerServerLabel(Map<String, dynamic> source, int index) {
  final fallback = 'Line ${index + 1}';
  final label = (source['label'] ?? source['resolution'] ?? '')
      .toString()
      .trim();
  if (label.isEmpty || label.length > 80) return fallback;
  if (RegExp(r'[/?:=&@\\]').hasMatch(label) ||
      RegExp(
        r'\b(?:referer|origin|authorization|token|key|kid)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(label) ||
      RegExp(r'\b[0-9a-f]{24,}\b', caseSensitive: false).hasMatch(label)) {
    return fallback;
  }
  final repeated = RegExp(
    r'^\s*([^·•|]+?)\s*[·•|]\s*\1(?=\s*[·•|]|$)',
    caseSensitive: false,
  ).firstMatch(label);
  if (repeated == null) return label;
  return label
      .replaceRange(repeated.start, repeated.end, repeated.group(1)!)
      .trim();
}

/// Current line plus a vertical chooser for an active player.
///
/// Only the public display label is rendered. Stream URLs, request headers and
/// key material are deliberately ignored.
class PlayerServerRail extends StatelessWidget {
  const PlayerServerRail({
    super.key,
    required this.sources,
    required this.selectedIndex,
    required this.onSelected,
    this.failedIndices = const <int>{},
    this.loadingIndex,
  });

  final List<Map<String, dynamic>> sources;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Set<int> failedIndices;
  final int? loadingIndex;

  @override
  Widget build(BuildContext context) {
    final visible = visiblePlaybackIndices(sources);
    if (visible.isEmpty) return const SizedBox.shrink();

    var selectedPrimary = selectedIndex;
    if (selectedIndex >= 0 &&
        selectedIndex < sources.length &&
        !isVisiblePlaybackLine(sources[selectedIndex])) {
      final fallbackId = (sources[selectedIndex]['id'] ?? '')
          .toString()
          .replaceFirst(RegExp(r'-vpn-free$'), '');
      for (final original in visible) {
        if ((sources[original]['id'] ?? '').toString() == fallbackId) {
          selectedPrimary = original;
          break;
        }
      }
    }
    final current = visible.contains(selectedPrimary)
        ? selectedPrimary
        : visible.first;
    final colors = Theme.of(context).colorScheme;
    String format(int index) {
      final type =
          (sources[index]['streamType'] ?? sources[index]['stream_type'] ?? '')
              .toString()
              .toLowerCase();
      return const {
            'hls': 'HLS',
            'dash': 'DASH',
            'mpd': 'DASH',
            'mp4': 'MP4',
            'flv': 'FLV',
          }[type] ??
          '';
    }

    return Material(
      key: const ValueKey('player-server-rail'),
      color: Colors.black,
      child: ListTile(
        dense: true,
        leading: Icon(
          Icons.check_rounded,
          key: ValueKey('player-line-check-$current'),
          color: colors.primary,
        ),
        title: Text(
          playerServerLabel(sources[current], current),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: format(current).isEmpty ? null : Text(format(current)),
        trailing: loadingIndex == current
            ? SizedBox(
                key: ValueKey('player-line-loading-$current'),
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            : const Icon(Icons.expand_more),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .6,
              child: Column(
                children: [
                  const ListTile(title: Text('Choose line')),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, position) {
                        final index = visible[position];
                        return ListTile(
                          key: ValueKey('player-line-chip-$index'),
                          selected: index == current,
                          leading: Icon(
                            index == current
                                ? Icons.check_rounded
                                : failedIndices.contains(index)
                                ? Icons.error_outline_rounded
                                : Icons.play_arrow,
                          ),
                          title: Text(playerServerLabel(sources[index], index)),
                          subtitle: format(index).isEmpty
                              ? null
                              : Text(format(index)),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            if (index != current) onSelected(index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
