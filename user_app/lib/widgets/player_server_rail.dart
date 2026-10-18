import 'package:flutter/material.dart';

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
  return label;
}

/// A compact, horizontally scrollable line selector for an active player.
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
    if (sources.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        height: 58,
        child: ListView.separated(
          key: const ValueKey('player-server-rail'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: sources.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final selected = index == selectedIndex;
            final failed = failedIndices.contains(index);
            final loading = loadingIndex == index;
            final label = playerServerLabel(sources[index], index);

            return Semantics(
              button: true,
              selected: selected,
              label: selected ? '$label, selected line' : '$label, line',
              child: Material(
                key: ValueKey('player-line-chip-$index'),
                color: selected
                    ? colors.primary.withValues(alpha: .18)
                    : const Color(0xFF171717),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected
                        ? colors.primary
                        : failed
                        ? colors.error.withValues(alpha: .72)
                        : Colors.white24,
                    width: selected ? 1.6 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: selected ? null : () => onSelected(index),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 82,
                      maxWidth: 190,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected) ...[
                            Icon(
                              Icons.check_rounded,
                              key: ValueKey('player-line-check-$index'),
                              size: 17,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                          ] else if (failed) ...[
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: colors.error,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? colors.primary : Colors.white,
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                          if (loading) ...[
                            const SizedBox(width: 7),
                            SizedBox(
                              key: ValueKey('player-line-loading-$index'),
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
