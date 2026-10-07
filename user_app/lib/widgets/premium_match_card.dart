import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PremiumMatchCard extends StatelessWidget {
  const PremiumMatchCard({
    super.key,
    required this.league,
    required this.homeName,
    required this.awayName,
    required this.kickoff,
    required this.isLive,
    required this.canWatch,
    required this.actionLabel,
    required this.onWatch,
    this.homeLogo,
    this.awayLogo,
    this.metaLabel,
  });

  final String league;
  final String homeName;
  final String awayName;
  final DateTime? kickoff;
  final bool isLive;
  final bool canWatch;
  final String actionLabel;
  final VoidCallback onWatch;
  final String? homeLogo;
  final String? awayLogo;
  final String? metaLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final accent = isLive ? Colors.redAccent : colors.primary;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.surface,
              colors.surfaceContainerHighest.withValues(alpha: dark ? .64 : .42),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: isLive ? .34 : .16),
          ),
          boxShadow: [
            BoxShadow(
              color: isLive
                  ? Colors.redAccent.withValues(alpha: dark ? .08 : .05)
                  : Colors.black.withValues(alpha: dark ? .13 : .05),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      league.isEmpty ? 'Football' : league,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurfaceVariant,
                        letterSpacing: .1,
                      ),
                    ),
                  ),
                  _StatusPill(
                    isLive: isLive,
                    kickoff: kickoff,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _Team(
                      name: homeName,
                      logo: homeLogo,
                    ),
                  ),
                  SizedBox(
                    width: 58,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'VS',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: colors.onSurface,
                          ),
                        ),
                        if (kickoff != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            DateFormat('dd MMM').format(kickoff!),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: _Team(
                      name: awayName,
                      logo: awayLogo,
                    ),
                  ),
                ],
              ),
              if ((metaLabel ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      metaLabel!,
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 9),
              _PremiumAction(
                enabled: canWatch,
                label: actionLabel,
                onTap: onWatch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.isLive,
    required this.kickoff,
  });

  final bool isLive;
  final DateTime? kickoff;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = isLive ? Colors.redAccent : colors.primary;
    final text = isLive
        ? 'LIVE'
        : kickoff == null
            ? 'SCHEDULED'
            : DateFormat('HH:mm').format(kickoff!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Team extends StatelessWidget {
  const _Team({
    required this.name,
    required this.logo,
  });

  final String name;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasLogo = logo != null && logo!.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .28),
            ),
          ),
          child: hasLogo
              ? Image.network(
                  logo!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.shield_outlined,
                    color: colors.onSurfaceVariant,
                    size: 23,
                  ),
                )
              : Icon(
                  Icons.shield_outlined,
                  color: colors.onSurfaceVariant,
                  size: 28,
                ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PremiumAction extends StatelessWidget {
  const _PremiumAction({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1 : .52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            height: 44,
            decoration: BoxDecoration(
              gradient: enabled
                  ? LinearGradient(
                      colors: [
                        colors.primary,
                        Color.lerp(colors.primary, colors.secondary, .36)!,
                      ],
                    )
                  : null,
              color: enabled
                  ? null
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: .20),
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  enabled ? Icons.play_arrow_rounded : Icons.schedule_rounded,
                  size: 20,
                  color: enabled
                      ? colors.onPrimary
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .15,
                    ),
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 5),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 21,
                    color: colors.onPrimary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
