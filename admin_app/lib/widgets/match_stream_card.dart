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
          const SizedBox(height: 8),
          Text(
            englishKnownFootballName(match['${side}_team']?.toString() ?? side),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Spacer(),
                  Expanded(
                    flex: 6,
                    child: Text(
                      '🏆 ${englishKnownFootballName(match['league']?.toString() ?? '', kind: 'league')}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    SizedBox(
                      width: 32,
                      height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'edit') onEdit?.call();
                          if (value == 'delete') onDelete?.call();
                        },
                        itemBuilder: (_) => [
                          if (onEdit != null)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit match'),
                            ),
                          if (onDelete != null)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete match'),
                            ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  team('home'),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(10),
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
                        const SizedBox(height: 8),
                        Text(
                          time == null
                              ? ''
                              : DateFormat('MMMM d', 'en_US').format(time),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  team('away'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
