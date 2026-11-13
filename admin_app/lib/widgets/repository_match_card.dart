import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/repository_logo.dart';

/// Repository fixture summary in the same compact layout as Live Edit & Delete.
/// Actions remain read-only here; line copying/import stays in the existing sheet.
class RepositoryMatchCard extends StatelessWidget {
  const RepositoryMatchCard({
    super.key,
    required this.entry,
    required this.onViewLines,
  });

  final Map<String, dynamic> entry;
  final VoidCallback onViewLines;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final meta = Map<String, dynamic>.from(entry['event_meta'] as Map? ?? {});
    final kickoff = DateTime.tryParse(meta['kickoff_at']?.toString() ?? '')
        ?.toUtc()
        .add(const Duration(hours: 6, minutes: 30));
    final count = (entry['stream_count'] as num?)?.toInt() ?? 0;
    final home = meta['home_team']?.toString().trim() ?? '';
    final away = meta['away_team']?.toString().trim() ?? '';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onViewLines,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  meta['league']?.toString() ?? 'Football',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _RepositoryTeam(
                      name: home.isEmpty ? 'Home' : home,
                      logo: meta['home_logo_url']?.toString() ?? '',
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            kickoff == null
                                ? 'Time pending'
                                : DateFormat('h:mm a', 'en_US').format(kickoff),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          kickoff == null
                              ? 'Not provided'
                              : '${DateFormat('dd MMM', 'en_US').format(kickoff)} · MMT',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _RepositoryTeam(
                      name: away.isEmpty ? 'Away' : away,
                      logo: meta['away_logo_url']?.toString() ?? '',
                    ),
                  ),
                ],
              ),
              if (home.isEmpty || away.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry['name']?.toString() ?? 'Football',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Divider(height: 17),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$count UNIQUE ${count == 1 ? 'LINE' : 'LINES'}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onViewLines,
                    icon: const Icon(Icons.playlist_play_rounded, size: 20),
                    label: const Text('VIEW LINES'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepositoryTeam extends StatelessWidget {
  const _RepositoryTeam({required this.name, required this.logo});
  final String name, logo;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        width: 48,
        height: 48,
        child: logo.isEmpty
            ? const Icon(Icons.shield_outlined, size: 36)
            : Image.network(
                repositoryLogoUrl(logo),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.shield_outlined, size: 36),
              ),
      ),
      const SizedBox(height: 5),
      Text(
        name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    ],
  );
}
