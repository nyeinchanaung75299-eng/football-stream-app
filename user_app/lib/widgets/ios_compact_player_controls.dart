import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Native iOS video overlay. Unlike AdaptiveVideoControls, this deliberately
/// has no oversized center transport, no Previous/Next and no fake qualities.
class IOSCompactPlayerControls extends StatelessWidget {
  const IOSCompactPlayerControls({
    super.key,
    required this.player,
    required this.playing,
    required this.rate,
    required this.onRateChanged,
  });

  final mk.Player player;
  final bool playing;
  final double rate;
  final ValueChanged<double> onRateChanged;

  String _time(Duration duration) {
    final total = duration.inSeconds.clamp(0, 999999);
    final seconds = (total % 60).toString().padLeft(2, '0');
    final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
    return total >= 3600 ? '${total ~/ 3600}:$minutes:$seconds' : '${total ~/ 60}:$seconds';
  }

  Widget _control(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: Colors.white),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      );

  Future<void> _chooseVideo(BuildContext context) async {
    final videos = player.state.tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no').toList();
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Resolution'), enabled: false),
          ListTile(title: const Text('Auto (adaptive)'), onTap: () {
            Navigator.pop(sheet);
            unawaited(player.setVideoTrack(mk.VideoTrack.auto()));
          }),
          for (final track in videos)
            ListTile(
              title: Text(track.h != null && track.h! > 0
                  ? '${track.h}p' : (track.title ?? 'Video track')),
              onTap: () {
                Navigator.pop(sheet);
                unawaited(player.setVideoTrack(track));
              },
            ),
        ],
      )),
    );
  }

  Future<void> _chooseAudio(BuildContext context) async {
    final audios = player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no').toList();
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Audio track'), enabled: false),
        ListTile(title: const Text('Auto'), onTap: () {
          Navigator.pop(sheet);
          unawaited(player.setAudioTrack(mk.AudioTrack.auto()));
        }),
        for (final track in audios)
          ListTile(
            title: Text(track.title ?? track.language ?? 'Audio track'),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(player.setAudioTrack(track));
            },
          ),
      ])),
    );
  }

  Future<void> _chooseSubtitles(BuildContext context) async {
    final subtitles = player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no').toList();
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Subtitles'), enabled: false),
        ListTile(title: const Text('Off'), onTap: () {
          Navigator.pop(sheet);
          unawaited(player.setSubtitleTrack(mk.SubtitleTrack.no()));
        }),
        for (final track in subtitles)
          ListTile(
            title: Text(track.title ?? track.language ?? 'Subtitle'),
            onTap: () {
              Navigator.pop(sheet);
              unawaited(player.setSubtitleTrack(track));
            },
          ),
      ])),
    );
  }

  Future<void> _chooseSpeed(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Playback speed'), enabled: false),
        for (final value in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          ListTile(
            title: Text(value == 1.0 ? 'Normal • 1×' : '${value}×'),
            trailing: rate == value ? const Icon(Icons.check_rounded) : null,
            onTap: () {
              Navigator.pop(sheet);
              onRateChanged(value);
              unawaited(player.setRate(value));
            },
          ),
      ])),
    );
  }

  Future<void> _settings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context, showDragHandle: true,
      builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Player settings'), enabled: false),
        ListTile(
          leading: const Icon(Icons.high_quality_rounded),
          title: const Text('Resolution'),
          subtitle: const Text('Available video tracks only'),
          onTap: () {
            Navigator.pop(sheet);
            unawaited(_chooseVideo(context));
          },
        ),
        ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: const Text('Playback speed'),
          onTap: () {
            Navigator.pop(sheet);
            unawaited(_chooseSpeed(context));
          },
        ),
        ListTile(
          leading: const Icon(Icons.subtitles_rounded),
          title: const Text('Subtitles'),
          onTap: () {
            Navigator.pop(sheet);
            unawaited(_chooseSubtitles(context));
          },
        ),
        ListTile(
          leading: const Icon(Icons.volume_up_rounded),
          title: const Text('Audio track'),
          onTap: () {
            Navigator.pop(sheet);
            unawaited(_chooseAudio(context));
          },
        ),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x35000000),
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          _control(Icons.replay_5_rounded, 'Back 5 seconds', () {
            final at = player.state.position;
            unawaited(player.seek(Duration(milliseconds:
                (at.inMilliseconds - 5000).clamp(0, 864000000))));
          }),
          _control(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            'Play or pause',
            () => unawaited(player.playOrPause()),
          ),
          _control(Icons.forward_15_rounded, 'Forward 15 seconds', () {
            final target = player.state.position + const Duration(seconds: 15);
            final duration = player.state.duration;
            unawaited(player.seek(duration > Duration.zero && target > duration
                ? duration : target));
          }),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, snapshot) {
              final duration = player.state.duration;
              final position = snapshot.data ?? Duration.zero;
              return Text(duration > Duration.zero
                      ? '${_time(position)} / ${_time(duration)}' : '● LIVE',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600));
            },
          ),
          Expanded(child: StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, snapshot) {
              final end = player.state.duration.inMilliseconds;
              final pos = (snapshot.data ?? Duration.zero).inMilliseconds;
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: end > 0 ? pos.clamp(0, end).toDouble() : 0,
                  max: end > 0 ? end.toDouble() : 1,
                  onChanged: end > 0
                      ? (value) => unawaited(player.seek(
                          Duration(milliseconds: value.round())))
                      : null,
                ),
              );
            },
          )),
          _control(Icons.settings_rounded, 'Resolution, audio and speed',
              () => unawaited(_settings(context))),
        ],
      ),
    ),
  );
}
