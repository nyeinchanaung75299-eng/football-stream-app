import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../analytics_service.dart';

/// Native iOS playback powered by libmpv/FFmpeg through package:media_kit.
///
/// Android deliberately keeps its Media3 player. Web/Safari keeps the shared
/// browser player. This page avoids WKWebView for the iOS app so live HLS/DASH
/// playback uses native decoding, caching and A/V sync.
class IOSPlayerPage extends StatefulWidget {
  const IOSPlayerPage({
    super.key,
    required this.sources,
    required this.selectedIndex,
    required this.title,
    required this.matchId,
  });

  final List<Map<String, dynamic>> sources;
  final int selectedIndex;
  final String title;
  final String matchId;

  @override
  State<IOSPlayerPage> createState() => _IOSPlayerPageState();
}

class _IOSPlayerPageState extends State<IOSPlayerPage> {
  late final mk.Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<int> _failedLines = <int>{};

  late int _selectedIndex;
  bool _opening = true;
  bool _buffering = false;
  bool _playing = false;
  bool _disposed = false;
  String? _errorText;
  Timer? _startupTimer;
  Timer? _stallTimer;
  int _playbackToken = 0;
  int _sameLineRecoveryCount = 0;

  @override
  void initState() {
    super.initState();
    mk.MediaKit.ensureInitialized();

    _selectedIndex = widget.sources.isEmpty
        ? 0
        : widget.selectedIndex.clamp(0, widget.sources.length - 1);

    _player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        // Large enough to absorb VPN jitter without forcing a huge startup
        // buffer. Native mpv cache controls below decide when playback begins.
        bufferSize: 48 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        scale: 1.0,
      ),
    );

    _listenToPlayer();
    unawaited(_openLine(_selectedIndex, userSelected: true));
  }

  void _listenToPlayer() {
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (_disposed) return;
        if (value) {
          _startupTimer?.cancel();
          _errorText = null;
          unawaited(_player.setRate(1.0));
        }
        if (mounted) {
          setState(() {
            _playing = value;
            if (value) _opening = false;
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((value) {
        if (_disposed) return;
        if (mounted) setState(() => _buffering = value);

        _stallTimer?.cancel();
        _stallTimer = null;
        if (value && _playing) {
          _stallTimer = Timer(const Duration(seconds: 9), () {
            if (!_disposed && _player.state.buffering) {
              unawaited(_recoverOrFallback('stall_timeout'));
            }
          });
        }
        if (value) {
          unawaited(
            AnalyticsService.capture(
              'playback buffering',
              properties: _eventProperties(),
            ),
          );
        }
      }),
    );

    _subscriptions.add(
      _player.stream.rate.listen((rate) {
        // A live stream must never drift into visibly slow playback.
        if (!_disposed && (rate - 1.0).abs() > 0.005) {
          unawaited(_player.setRate(1.0));
        }
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((_) {
        if (_disposed) return;
        // libmpv may report recoverable network details while its cache is
        // refilling. Give an already-playing line a brief recovery window.
        if (_playing) {
          _stallTimer?.cancel();
          _stallTimer = Timer(const Duration(seconds: 4), () {
            if (!_disposed && (_player.state.buffering || !_player.state.playing)) {
              unawaited(_recoverOrFallback('playback_error'));
            }
          });
          return;
        }
        unawaited(_recoverOrFallback('playback_error'));
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!_disposed && completed && widget.sources.length > 1) {
          unawaited(_fallbackToNext('playback_ended'));
        }
      }),
    );
  }

  Map<String, Object> _eventProperties({int? fromIndex, int? toIndex}) {
    final source = widget.sources.isEmpty
        ? const <String, dynamic>{}
        : widget.sources[_selectedIndex];
    return <String, Object>{
      if (widget.matchId.isNotEmpty) 'match_id': widget.matchId,
      'selected_index': _selectedIndex,
      'line_count': widget.sources.length,
      'stream_type': _sourceType(source),
      if (fromIndex != null) 'from_index': fromIndex,
      if (toIndex != null) 'to_index': toIndex,
    };
  }

  String _sourceType(Map<String, dynamic> source) {
    final declared =
        (source['streamType'] ?? source['stream_type'] ?? 'auto')
            .toString()
            .trim()
            .toLowerCase();
    if (declared == 'm3u8') return 'hls';
    if (declared == 'mpd') return 'dash';
    if (const {'hls', 'dash', 'mp4', 'flv'}.contains(declared)) {
      return declared;
    }

    final url = (source['url'] ?? source['stream_url'] ?? '')
        .toString()
        .toLowerCase();
    if (url.contains('.m3u8')) return 'hls';
    if (url.contains('.mpd')) return 'dash';
    if (url.contains('.mp4')) return 'mp4';
    if (url.contains('.flv')) return 'flv';
    return 'auto';
  }

  String _lineLabel(Map<String, dynamic> source, int index) {
    final label = (source['label'] ?? source['resolution'] ?? '')
        .toString()
        .trim();
    return label.isEmpty ? 'Line ${index + 1}' : label;
  }

  Map<String, String> _headersFor(Map<String, dynamic> source) {
    final headers = <String, String>{};
    final referer = (source['referer'] ?? '').toString().trim();
    final origin = (source['origin'] ?? '').toString().trim();
    if (referer.startsWith('http://') || referer.startsWith('https://')) {
      headers['Referer'] = referer;
    }
    if (origin.startsWith('http://') || origin.startsWith('https://')) {
      headers['Origin'] = origin;
    }
    return headers;
  }

  String _normalizedCencKey(Map<String, dynamic> source) {
    final raw = (source['keyData'] ?? source['key_data'] ?? '')
        .toString()
        .trim()
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .toLowerCase();
    return raw.length == 32 ? raw : '';
  }

  Future<mk.NativePlayer?> _nativePlayer() async {
    try {
      await _player.handle;
      final platform = _player.platform;
      return platform is mk.NativePlayer ? platform : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _configureForSource(Map<String, dynamic> source) async {
    final native = await _nativePlayer();
    if (native == null) return;

    // Audio-clock sync is mpv's most robust mode and prevents display timing
    // from subtly changing playback speed on mobile displays.
    await native.setProperty('video-sync', 'audio');
    await native.setProperty('cache', 'yes');
    await native.setProperty('cache-secs', '8');
    await native.setProperty('cache-pause', 'yes');
    await native.setProperty('cache-pause-wait', '1');
    await native.setProperty('cache-pause-initial', 'yes');
    await native.setProperty('demuxer-readahead-secs', '8');
    await native.setProperty('demuxer-max-bytes', '48MiB');

    // Never leak format/key options from the previously selected line.
    await native.setProperty('demuxer-lavf-format', '');
    await native.setProperty('demuxer-lavf-o', '');

    final type = _sourceType(source);
    if (type == 'hls') {
      await native.setProperty('demuxer-lavf-format', 'hls');
      // Prefer a stable live rendition over immediately pulling the heaviest
      // variant through a VPN. Users can still choose another server/line.
      await native.setProperty('hls-bitrate', '3000000');
    } else if (type == 'dash') {
      await native.setProperty('demuxer-lavf-format', 'dash');
      final key = _normalizedCencKey(source);
      if (key.isNotEmpty) {
        // This key is the already-authorized per-line key supplied by Admin.
        // FFmpeg's DASH demuxer consumes it locally; it is never logged.
        await native.setProperty(
          'demuxer-lavf-o',
          'cenc_decryption_key=$key',
        );
      }
    }
    await _player.setRate(1.0);
  }

  Future<void> _openLine(
    int index, {
    bool userSelected = false,
    bool recovery = false,
  }) async {
    if (_disposed || widget.sources.isEmpty) return;
    index = index.clamp(0, widget.sources.length - 1);

    final token = ++_playbackToken;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    if (userSelected) {
      _failedLines.clear();
      _sameLineRecoveryCount = 0;
    }

    if (mounted) {
      setState(() {
        _selectedIndex = index;
        _opening = true;
        _buffering = true;
        _errorText = null;
      });
    } else {
      _selectedIndex = index;
    }

    final source = widget.sources[index];
    final url = (source['url'] ?? source['stream_url'] ?? '')
        .toString()
        .trim();
    if (url.isEmpty) {
      await _fallbackToNext('empty_source');
      return;
    }

    try {
      await _player.stop();
      if (_disposed || token != _playbackToken) return;
      await _configureForSource(source);
      if (_disposed || token != _playbackToken) return;

      final media = mk.Media(
        url,
        httpHeaders: _headersFor(source),
        extras: <String, dynamic>{
          'line_index': index,
          'stream_type': _sourceType(source),
        },
      );

      // open(play: true) keeps startup to one native operation.
      await _player.open(media, play: true);
      if (_disposed || token != _playbackToken) return;

      _startupTimer = Timer(
        Duration(seconds: _sourceType(source) == 'dash' ? 12 : 10),
        () {
          if (!_disposed && token == _playbackToken && !_player.state.playing) {
            unawaited(_fallbackToNext('startup_timeout'));
          }
        },
      );

      unawaited(
        AnalyticsService.capture(
          recovery ? 'playback line recovery' : 'playback line selected',
          properties: _eventProperties(),
        ),
      );
    } catch (_) {
      if (!_disposed && token == _playbackToken) {
        await _fallbackToNext('playback_error');
      }
    }
  }

  Future<void> _recoverOrFallback(String reason) async {
    if (_disposed || widget.sources.isEmpty) return;

    if (_sameLineRecoveryCount < 1) {
      _sameLineRecoveryCount += 1;
      unawaited(
        AnalyticsService.capture(
          'playback native recovery',
          properties: <String, Object>{
            ..._eventProperties(),
            'reason': reason,
          },
        ),
      );
      await _openLine(
        _selectedIndex,
        recovery: true,
      );
      return;
    }

    await _fallbackToNext(reason);
  }

  int _fallbackRank(int index) {
    final type = _sourceType(widget.sources[index]);
    return switch (type) {
      'hls' => 0,
      'dash' => 1,
      'mp4' => 2,
      'auto' => 3,
      'flv' => 9,
      _ => 6,
    };
  }

  Future<void> _fallbackToNext(String reason) async {
    if (_disposed || widget.sources.isEmpty) return;

    final from = _selectedIndex;
    _failedLines.add(from);
    final candidates = List<int>.generate(widget.sources.length, (i) => i)
      ..removeWhere(_failedLines.contains)
      ..sort((a, b) {
        final rank = _fallbackRank(a).compareTo(_fallbackRank(b));
        return rank != 0 ? rank : a.compareTo(b);
      });

    unawaited(
      AnalyticsService.capture(
        'playback line failed',
        properties: <String, Object>{
          ..._eventProperties(),
          'reason': reason,
        },
      ),
    );

    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _opening = false;
          _buffering = false;
          _playing = false;
          _errorText =
              'This stream is not stable on iPhone. Try another line.';
        });
      }
      return;
    }

    final next = candidates.first;
    _sameLineRecoveryCount = 0;
    unawaited(
      AnalyticsService.capture(
        'playback auto fallback',
        properties: <String, Object>{
          ..._eventProperties(fromIndex: from, toIndex: next),
          'reason': reason,
        },
      ),
    );
    await _openLine(next);
  }

  Future<void> _pickLine() async {
    if (!mounted || widget.sources.isEmpty) return;
    final colors = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: colors.surface,
      builder: (sheetContext) {
        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          itemCount: widget.sources.length,
          separatorBuilder: (_, __) => const SizedBox(height: 5),
          itemBuilder: (_, index) {
            final source = widget.sources[index];
            final selected = index == _selectedIndex;
            final type = _sourceType(source).toUpperCase();
            return ListTile(
              onTap: () => Navigator.of(sheetContext).pop(index),
              selected: selected,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Icon(
                selected
                    ? Icons.play_circle_fill_rounded
                    : Icons.play_circle_outline_rounded,
              ),
              title: Text(
                _lineLabel(source, index),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                type == 'DASH'
                    ? 'MPD • native iOS'
                    : '$type • native iOS',
              ),
              trailing: selected
                  ? Icon(Icons.check_rounded, color: colors.primary)
                  : null,
            );
          },
        );
      },
    );

    if (picked == null || _disposed) return;
    await _openLine(picked, userSelected: true);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_playbackToken;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = widget.sources.isEmpty
        ? const <String, dynamic>{}
        : widget.sources[_selectedIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              _lineLabel(source, _selectedIndex) +
                  ' • ' +
                  _sourceType(source).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _pickLine,
            icon: const Icon(Icons.dns_rounded, size: 18),
            label: Text(
              widget.sources.length > 1
                  ? '${widget.sources.length} Lines'
                  : 'Line',
            ),
            style: TextButton.styleFrom(foregroundColor: colors.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.sources.isNotEmpty)
              Video(
                controller: _videoController,
                fit: BoxFit.contain,
                fill: Colors.black,
                controls: AdaptiveVideoControls,
                wakelock: true,
                pauseUponEnteringBackgroundMode: true,
                resumeUponEnteringForegroundMode: false,
              ),
            if (_opening || _buffering)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .68),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _playing ? 'Buffering…' : 'Starting stream…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_errorText != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(18),
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
                        color: Colors.white70,
                        size: 34,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _pickLine,
                        icon: const Icon(Icons.dns_rounded),
                        label: const Text('CHOOSE ANOTHER LINE'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
