import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';

import '../analytics_service.dart';
import '../native_playback_progress.dart';

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
    this.sourceUpdates,
    this.onClosed,
  });

  final List<Map<String, dynamic>> sources;
  final int selectedIndex;
  final String title;
  final String matchId;
  final ValueListenable<int>? sourceUpdates;
  final VoidCallback? onClosed;

  @override
  State<IOSPlayerPage> createState() => _IOSPlayerPageState();
}

class _IOSPlayerPageState extends State<IOSPlayerPage>
    with WidgetsBindingObserver {
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
  Timer? _progressTimer;
  Timer? _stallTimer;
  int _playbackToken = 0;
  int _sameLineRecoveryCount = 0;
  int? _recoveryRequestedFor;
  bool _acceptProgress = false;
  bool _sawPlayingInAttempt = false;
  bool _foreground = true;
  bool _userPaused = false;
  NativePlaybackProgress? _progress;
  final Stopwatch _attemptClock = Stopwatch();
  Duration? _bufferStartedAt;
  String? _bufferPhase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.sourceUpdates?.addListener(_onSourcesUpdated);
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

  void _onSourcesUpdated() {
    // NativePlayer appends backup rows to this session's list. Keep the current
    // index and decoder untouched; only refresh the picker and line count.
    if (!_disposed && mounted) setState(() {});
  }

  void _listenToPlayer() {
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (_disposed) return;
        if (_acceptProgress && (value || _sawPlayingInAttempt)) {
          if (value) _sawPlayingInAttempt = true;
          _userPaused = !value;
          _syncProgressSuspension();
        }
        if (value) {
          unawaited(_player.setRate(1.0));
        }
        if (mounted) {
          setState(() => _playing = value);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((value) {
        if (_disposed || !_acceptProgress) return;
        if (mounted) setState(() => _buffering = value);
        // A buffering=false notification can precede useful media. End the
        // episode only when the media clock actually advances.
        if (value && _foreground && !_userPaused) _beginBuffering();
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((position) {
        final progress = _progress;
        if (_disposed || !_acceptProgress || progress == null || !_playing) {
          return;
        }
        final wasStarted = progress.started;
        if (!progress.observePosition(position, _attemptClock.elapsed)) return;
        _stallTimer?.cancel();
        _endBuffering();
        if (mounted && (_opening || _buffering || _errorText != null)) {
          setState(() {
            _opening = false;
            _buffering = false;
            _errorText = null;
          });
        }
        if (!wasStarted) {
          unawaited(
            AnalyticsService.capture(
              'playback started',
              properties: <String, Object>{
                ..._eventProperties(),
                'startup_ms': progress.startupElapsed!.inMilliseconds,
              },
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
        if (_disposed || !_acceptProgress || !_foreground || _userPaused)
          return;
        // libmpv may report recoverable network details while its cache is
        // refilling. Give an already-playing line a brief recovery window.
        if (_progress?.started == true) {
          final token = _playbackToken;
          _stallTimer?.cancel();
          _stallTimer = Timer(const Duration(seconds: 4), () {
            if (!_disposed &&
                token == _playbackToken &&
                _foreground &&
                !_userPaused &&
                (_player.state.buffering || !_player.state.playing)) {
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
        if (!_disposed && _acceptProgress && _foreground && completed) {
          if (_sourceType(widget.sources[_selectedIndex]) == 'mp4') {
            // A finite file ending normally is not a failed live stream. Keep
            // the watchdog suspended until the user starts playback again.
            _userPaused = true;
            _syncProgressSuspension();
            return;
          }
          // Native completion can also set playing=false; that is not a
          // deliberate user pause and must not disable recovery.
          _userPaused = false;
          _syncProgressSuspension();
          unawaited(_recoverOrFallback('playback_ended'));
        }
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stallTimer?.cancel();
    _syncProgressSuspension();
  }

  void _syncProgressSuspension() {
    _progress?.setSuspended(!_foreground || _userPaused, _attemptClock.elapsed);
    if (!_foreground || _userPaused) _stallTimer?.cancel();
  }

  void _beginBuffering() {
    final progress = _progress;
    if (progress == null || _bufferStartedAt != null) return;
    _bufferStartedAt = progress.activeElapsed(_attemptClock.elapsed);
    _bufferPhase = progress.started ? 'rebuffer' : 'startup';
    unawaited(
      AnalyticsService.capture(
        'playback buffering',
        properties: <String, Object>{
          ..._eventProperties(),
          'phase': _bufferPhase!,
        },
      ),
    );
  }

  void _endBuffering() {
    final progress = _progress;
    final start = _bufferStartedAt;
    if (progress == null || start == null) return;
    final elapsed = progress.activeElapsed(_attemptClock.elapsed) - start;
    unawaited(
      AnalyticsService.capture(
        'playback buffering ended',
        properties: <String, Object>{
          ..._eventProperties(),
          'phase': _bufferPhase!,
          'buffering_ms': elapsed.inMilliseconds,
        },
      ),
    );
    _bufferStartedAt = null;
    _bufferPhase = null;
  }

  Map<String, Object> _eventProperties({int? fromIndex, int? toIndex}) {
    final source = widget.sources.isEmpty
        ? const <String, dynamic>{}
        : widget.sources[_selectedIndex];
    final lineId = (source['id'] ?? source['lineId'] ?? source['line_id'] ?? '')
        .toString()
        .trim();
    final uri = Uri.tryParse(
      (source['url'] ?? source['stream_url'] ?? '').toString().trim(),
    );
    return <String, Object>{
      if (RegExp(r'^[A-Za-z0-9_:-]{1,128}$').hasMatch(widget.matchId))
        'match_id': widget.matchId,
      'selected_index': _selectedIndex,
      'line_count': widget.sources.length,
      'stream_type': _sourceType(source),
      if (RegExp(r'^[A-Za-z0-9_:-]{1,128}$').hasMatch(lineId))
        'line_id': lineId,
      if (uri != null &&
          const {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty)
        'route': uri.host,
      if (fromIndex != null) 'from_index': fromIndex,
      if (toIndex != null) 'to_index': toIndex,
    };
  }

  String _sourceType(Map<String, dynamic> source) {
    final declared = (source['streamType'] ?? source['stream_type'] ?? 'auto')
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

  Future<bool> _configureForSource(
    Map<String, dynamic> source,
    int token,
  ) async {
    final native = await _nativePlayer();
    bool current() => !_disposed && token == _playbackToken;
    if (!current()) return false;
    if (native == null) return true;
    Future<bool> property(String name, String value) async {
      if (!current()) return false;
      await native.setProperty(name, value);
      return current();
    }

    // Audio-clock sync is mpv's most robust mode and prevents display timing
    // from subtly changing playback speed on mobile displays.
    for (final entry in const <String, String>{
      'video-sync': 'audio',
      'cache': 'yes',
      'cache-secs': '8',
      'cache-pause': 'yes',
      'cache-pause-wait': '1',
      'cache-pause-initial': 'yes',
      'demuxer-readahead-secs': '8',
      'demuxer-max-bytes': '48MiB',
      // Never leak format/key options from the previously selected line.
      'demuxer-lavf-format': '',
      'demuxer-lavf-o': '',
    }.entries) {
      if (!await property(entry.key, entry.value)) return false;
    }

    final type = _sourceType(source);
    if (type == 'hls') {
      if (!await property('demuxer-lavf-format', 'hls')) return false;
      // Prefer a stable live rendition over immediately pulling the heaviest
      // variant through a VPN. Users can still choose another server/line.
      if (!await property('hls-bitrate', '3000000')) return false;
    } else if (type == 'dash') {
      if (!await property('demuxer-lavf-format', 'dash')) return false;
      final key = _normalizedCencKey(source);
      if (key.isNotEmpty) {
        // This key is the already-authorized per-line key supplied by Admin.
        // FFmpeg's DASH demuxer consumes it locally; it is never logged.
        if (!await property('demuxer-lavf-o', 'cenc_decryption_key=$key'))
          return false;
      }
    }
    await _player.setRate(1.0);
    return current();
  }

  Future<void> _openLine(
    int index, {
    bool userSelected = false,
    bool recovery = false,
  }) async {
    if (_disposed || widget.sources.isEmpty) return;
    index = index.clamp(0, widget.sources.length - 1);

    final token = ++_playbackToken;
    _progressTimer?.cancel();
    _stallTimer?.cancel();
    _acceptProgress = false;
    _sawPlayingInAttempt = false;
    _userPaused = false;
    _progress = NativePlaybackProgress();
    _attemptClock
      ..reset()
      ..start();
    _bufferStartedAt = null;
    _bufferPhase = null;
    _syncProgressSuspension();
    // Arm before stop/configuration/open: any of those native awaits can hang.
    // playing=true only means mpv is unpaused, not that a frame has arrived.
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || token != _playbackToken) return;
      final reason = _progress?.timeoutReason(_attemptClock.elapsed);
      if (reason != null) unawaited(_recoverOrFallback(reason));
    });
    if (userSelected) {
      _failedLines.clear();
      _sameLineRecoveryCount = 0;
    }

    if (mounted) {
      setState(() {
        _selectedIndex = index;
        _opening = true;
        _buffering = true;
        _playing = false;
        _errorText = null;
      });
    } else {
      _selectedIndex = index;
    }

    final source = widget.sources[index];
    final url = (source['url'] ?? source['stream_url'] ?? '').toString().trim();
    if (url.isEmpty) {
      await _fallbackToNext('empty_source');
      return;
    }

    if (_foreground) _beginBuffering();
    unawaited(
      AnalyticsService.capture(
        recovery ? 'playback line recovery' : 'playback line selected',
        properties: _eventProperties(),
      ),
    );

    try {
      await _player.stop();
      if (_disposed || token != _playbackToken) return;
      if (!await _configureForSource(source, token)) return;

      final media = mk.Media(
        url,
        httpHeaders: _headersFor(source),
        extras: <String, dynamic>{
          'line_index': index,
          'stream_type': _sourceType(source),
        },
      );

      // open(play: true) keeps startup to one native operation.
      _acceptProgress = true;
      await _player.open(media, play: true);
      if (_disposed || token != _playbackToken) return;
    } catch (_) {
      if (!_disposed && token == _playbackToken) {
        await _recoverOrFallback('playback_error');
      }
    }
  }

  Future<void> _recoverOrFallback(String reason) async {
    if (_disposed ||
        widget.sources.isEmpty ||
        !_foreground ||
        _userPaused ||
        _recoveryRequestedFor == _playbackToken)
      return;
    // Claim this generation synchronously. A delayed error and watchdog cannot
    // both switch lines, and a stuck old open cannot disable the new deadline.
    _recoveryRequestedFor = _playbackToken;

    if (_sameLineRecoveryCount < 1) {
      _sameLineRecoveryCount += 1;
      unawaited(
        AnalyticsService.capture(
          'playback native recovery',
          properties: <String, Object>{..._eventProperties(), 'reason': reason},
        ),
      );
      await _openLine(_selectedIndex, recovery: true);
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

    _progressTimer?.cancel();
    _stallTimer?.cancel();
    _acceptProgress = false;
    ++_playbackToken;

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
        properties: <String, Object>{..._eventProperties(), 'reason': reason},
      ),
    );

    if (candidates.isEmpty) {
      if (mounted) {
        setState(() {
          _opening = false;
          _buffering = false;
          _playing = false;
          _errorText = 'This stream is not stable on iPhone. Try another line.';
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
                type == 'DASH' ? 'MPD • native iOS' : '$type • native iOS',
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
    WidgetsBinding.instance.removeObserver(this);
    widget.sourceUpdates?.removeListener(_onSourcesUpdated);
    widget.onClosed?.call();
    ++_playbackToken;
    _progressTimer?.cancel();
    _stallTimer?.cancel();
    _attemptClock.stop();
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
              style: const TextStyle(color: Colors.white60, fontSize: 10.5),
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
                          _progress?.started == true
                              ? 'Buffering…'
                              : 'Starting stream…',
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
                        Icons
                            .signal_wifi_statusbar_connected_no_internet_4_rounded,
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
