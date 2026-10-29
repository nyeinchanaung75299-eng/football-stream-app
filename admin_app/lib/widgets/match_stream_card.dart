import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../football_english.dart';

/// A whole match is one tap target for adding its live links.
class MatchStreamCard extends StatelessWidget {
  const MatchStreamCard({
    super.key,
    required this.match,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });
  final Map<String, dynamic> match;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  Widget team(String side) {
    final logo = match['${side}_logo_url']?.toString() ?? '';
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 48,
            width: 48,
            child: logo.startsWith('https://')
                ? Image.network(
                    logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.sports_soccer, size: 36),
                  )
                : const Icon(Icons.sports_soccer, size: 36),
          ),
          const SizedBox(height: 5),
          Text(
            englishKnownFootballName(match['${side}_team']?.toString() ?? side),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time =
        DateTime.tryParse(match['kickoff_at']?.toString() ?? '')?.toLocal();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      englishKnownFootballName(
                        match['league']?.toString() ?? '',
                        kind: 'league',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _StatusPill(isLive: match['is_live'] == true),
                  if (onEdit != null)
                    IconButton(
                      tooltip: 'Edit live match',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded, size: 20),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Delete live match',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: colors.error,
                        size: 21,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  team('home'),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            time == null
                                ? '--:--'
                                : DateFormat('h:mm a', 'en_US').format(time),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  team('away'),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('LIVE LINKS'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isLive});

  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (isLive ? colors.error : colors.primary).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isLive ? 'LIVE' : 'UPCOMING',
        style: TextStyle(
          color: isLive ? colors.error : colors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .45,
        ),
      ),
    );
  }
}
