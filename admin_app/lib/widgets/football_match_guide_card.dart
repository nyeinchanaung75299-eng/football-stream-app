import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Visual tokens from the user's My Channels Match Guide reference site.
abstract final class FootballGuideColors {
  static const background = Color(0xFF080D17);
  static const surface = Color(0xFF121A29);
  static const card = Color(0xFF18283B);
  static const inner = Color(0xFF1D3245);
  static const border = Color(0xFF314258);
  static const mint = Color(0xFF54E6C1);
  static const text = Color(0xFFF0F5FF);
  static const muted = Color(0xFF9EB2C9);
}

class FootballGuideAiring {
  const FootballGuideAiring({
    required this.channel,
    required this.when,
    this.region = '',
    this.source = 'EPG schedule',
  });
  final String channel;
  final DateTime when;
  final String region;
  final String source;
}

class FootballMatchGuideCard extends StatelessWidget {
  const FootballMatchGuideCard({
    super.key,
    required this.league,
    required this.match,
    required this.kickoff,
    required this.live,
    this.airings = const [],
  });

  final String league;
  final String match;
  final DateTime? kickoff;
  final bool live;
  final List<FootballGuideAiring> airings;

  String _clock(DateTime date) =>
      DateFormat('EEE, MMM d • hh:mm a', 'en_US').format(
        date.toUtc().add(const Duration(hours: 6, minutes: 30)),
      );

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: FootballGuideColors.card,
      border: Border.all(color: FootballGuideColors.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(league,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: FootballGuideColors.muted,
              fontWeight: FontWeight.w800, fontSize: 13,
            ),
          )),
          Text(live ? 'LIVE' : 'UPCOMING',
            style: const TextStyle(
              color: FootballGuideColors.mint,
              fontWeight: FontWeight.w900, fontSize: 12,
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(match, style: const TextStyle(
          color: FootballGuideColors.text,
          fontSize: 19, fontWeight: FontWeight.w900, height: 1.28,
        )),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 15,
              color: FootballGuideColors.muted),
          const SizedBox(width: 5),
          Flexible(child: Text(
            kickoff == null ? 'Kickoff time unavailable' : '${_clock(kickoff!)} MMT',
            style: const TextStyle(
              color: FootballGuideColors.muted, fontSize: 12,
            ),
          )),
        ]),
        const SizedBox(height: 15),
        const Divider(color: FootballGuideColors.border, height: 1),
        const SizedBox(height: 12),
        const Text('🔴  LIVE ONLY • YOUR CHANNELS', style: TextStyle(
          color: FootballGuideColors.muted, fontWeight: FontWeight.w900,
          fontSize: 11, letterSpacing: 1.1,
        )),
        const SizedBox(height: 10),
        if (airings.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FootballGuideColors.surface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Text('No verified football EPG airing for your channels.',
              style: TextStyle(color: FootballGuideColors.muted, fontSize: 12)),
          )
        else
          for (final airing in airings) Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FootballGuideColors.inner,
              border: Border.all(color: const Color(0xFF305067)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📺 ${airing.channel}', style: const TextStyle(
                  color: FootballGuideColors.text, fontWeight: FontWeight.w850,
                  fontSize: 15,
                )),
                const SizedBox(height: 4),
                Text(
                  'LIVE • ${airing.source} • ${_clock(airing.when)} MMT'
                  '${airing.region.isEmpty ? '' : ' • ${airing.region.toUpperCase()}'}',
                  style: const TextStyle(
                    color: Color(0xFFA9D7D2), fontSize: 12, height: 1.5,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
