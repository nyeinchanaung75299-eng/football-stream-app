import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/tv_schedule_service.dart';
import 'channels_page.dart';

/// Compact, schedule-first view of the Admin's TV channel guide.
///
/// Catalog editing stays available through the small manage button, while the
/// default view intentionally shows only live and next match times. Replay
/// programmes are filtered in [TvScheduleGuide].
class MyChannelsGuidePage extends StatefulWidget {
  const MyChannelsGuidePage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MyChannelsGuidePage> createState() => _MyChannelsGuidePageState();
}

class _MyChannelsGuidePageState extends State<MyChannelsGuidePage> {
  late Future<TvScheduleGuide> _guide = _load();

  Future<TvScheduleGuide> _load() => TvScheduleService().load();

  void _refresh() => setState(() => _guide = _load());

  Future<void> _openManager() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChannelsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<TvScheduleGuide>(
      future: _guide,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GuideRetry(onRetry: _refresh);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final listings = snapshot.data!.liveAndUpcomingMatchListings();
        final byChannel = <String, List<TvScheduleListing>>{};
        for (final listing in listings) {
          byChannel
              .putIfAbsent(listing.channel.id, () => <TvScheduleListing>[])
              .add(listing);
        }
        final channelListings = byChannel.values.toList(growable: false);

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            children: [
              if (widget.embedded)
                _GuideHeader(
                  onRefresh: _refresh,
                  onManage: _openManager,
                ),
              if (widget.embedded) const SizedBox(height: 10),
              Text(
                '${channelListings.length} CHANNEL${channelListings.length == 1 ? '' : 'S'} • LIVE & NEXT MATCHES',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .65,
                ),
              ),
              const SizedBox(height: 7),
              if (channelListings.isEmpty)
                const _NoChannelMatches()
              else
                ...channelListings.map(
                  (items) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ChannelScheduleCard(listings: items),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Channels'),
        actions: [
          IconButton(
            tooltip: 'Refresh channel guide',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Manage channels',
            onPressed: _openManager,
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
      body: content,
    );
  }
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.onRefresh, required this.onManage});

  final VoidCallback onRefresh;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Channels',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Live and next match times only • MMT',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh channel guide',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Manage channels',
          onPressed: onManage,
          icon: const Icon(Icons.edit_note_rounded),
        ),
      ],
    );
  }
}

class _ChannelScheduleCard extends StatelessWidget {
  const _ChannelScheduleCard({required this.listings});

  final List<TvScheduleListing> listings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final channel = listings.first.channel;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ChannelImage(channel: channel),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      if (channel.region.isNotEmpty)
                        Text(
                          channel.region.toUpperCase(),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (listings.any((listing) => listing.isLive))
                  const _LivePill(label: 'LIVE'),
              ],
            ),
            const SizedBox(height: 8),
            for (final listing in listings.take(2)) ...[
              _ProgrammeRow(listing: listing),
              if (listing != listings.take(2).last) const Divider(height: 14),
            ],
            if (listings.length > 2) ...[
              const SizedBox(height: 2),
              Text(
                '+${listings.length - 2} more upcoming match${listings.length == 3 ? '' : 'es'}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelImage extends StatelessWidget {
  const _ChannelImage({required this.channel});

  final TvScheduleChannel channel;

  @override
  Widget build(BuildContext context) {
    final image = channel.imageUrl;
    final fallback = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.tv_rounded,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: 21,
      ),
    );
    if (!image.startsWith('http')) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        image,
        width: 38,
        height: 38,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _ProgrammeRow extends StatelessWidget {
  const _ProgrammeRow({required this.listing});

  final TvScheduleListing listing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final programme = listing.programme;
    final title = _programmeTitle(programme);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LivePill(label: listing.isLive ? 'LIVE' : 'NEXT'),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _timeLabel(programme.start),
          style: TextStyle(
            color: colors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final live = label == 'LIVE';
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (live ? colors.error : colors.primary).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: live ? colors.error : colors.primary,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: .45,
        ),
      ),
    );
  }
}

class _NoChannelMatches extends StatelessWidget {
  const _NoChannelMatches();

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No live or upcoming TV matches are listed right now.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

class _GuideRetry extends StatelessWidget {
  const _GuideRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 34),
              const SizedBox(height: 10),
              const Text(
                'Could not load the TV guide.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}

String _programmeTitle(TvScheduleProgramme programme) {
  final title = programme.title.trim();
  final subtitle = programme.subtitle.trim();
  if (RegExp(r'\b(?:vs|v|versus)\b', caseSensitive: false).hasMatch(title)) {
    return title;
  }
  if (RegExp(r'\b(?:vs|v|versus)\b', caseSensitive: false)
      .hasMatch(subtitle)) {
    return subtitle;
  }
  return title.isEmpty ? subtitle : title;
}

String _timeLabel(DateTime value) {
  final time = value.toUtc().add(const Duration(hours: 6, minutes: 30));
  final today = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 6, minutes: 30));
  final sameDay = time.year == today.year &&
      time.month == today.month &&
      time.day == today.day;
  final clock = DateFormat('h:mm a', 'en_US').format(time);
  if (sameDay) return '$clock MMT';
  return '${DateFormat('EEE', 'en_US').format(time)} $clock MMT';
}
