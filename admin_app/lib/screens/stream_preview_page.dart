import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/stream_detector_service.dart';
import '../services/stream_preview_diagnostics.dart';

/// An actual playback check, rather than treating HTTP 200 as a playable video.
class StreamPreviewPage extends StatefulWidget {
  const StreamPreviewPage({super.key, required this.stream});

  final DetectedStream stream;

  @override
  State<StreamPreviewPage> createState() => _StreamPreviewPageState();
}

class _StreamPreviewPageState extends State<StreamPreviewPage> {
  late final VideoPlayerController _player;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    final headers = <String, String>{
      if (widget.stream.referer.isNotEmpty) 'Referer': widget.stream.referer,
      if (widget.stream.origin.isNotEmpty) 'Origin': widget.stream.origin,
    };
    _player = VideoPlayerController.networkUrl(
      Uri.parse(widget.stream.url),
      // Browsers prevent overriding Referer/Origin on video requests.
      httpHeaders: kIsWeb ? const <String, String>{} : headers,
    );
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    await _player.initialize().timeout(const Duration(seconds: 20));
    if (!kIsWeb) await _player.play();
  }

  Future<void> _openSourcePage() async {
    final source = sourcePlayerPage(widget.stream.referer);
    if (source == null) return;
    try {
      // The originating website can run its normal player in its own browser
      // context. This is NOT a direct-HLS playback workaround or auth bypass.
      final opened = await launchUrl(
        source,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open source website.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open source website.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Test Stream')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                previewUrlForDisplay(widget.stream.url),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: FutureBuilder<void>(
                    future: _ready,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 36,
                                color: Colors.orangeAccent,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Stream detected, but playback failed',
                                style: TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                explainPreviewError(
                                  snapshot.error,
                                  isWeb: kIsWeb,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (hasTemporaryLinkParameters(
                                widget.stream.url,
                              )) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'This URL has parameters that may be '
                                  'short-lived. Return to Stream Detector, '
                                  'scan again and test the new link promptly.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              if (kIsWeb) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Web players cannot force the original '
                                  'website Referer, Origin or Cookie headers. '
                                  'If the source requires them, test playback '
                                  'on the authorized source website. Do not '
                                  'attempt to bypass its access controls.',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const SizedBox(height: 14),
                              if (sourcePlayerPage(widget.stream.referer) != null) ...[
                                FilledButton.icon(
                                  onPressed: _openSourcePage,
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open Original Player'),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Opens the source page in your browser, not '
                                  'the extracted M3U8 URL. The website may '
                                  'play there even when standalone playback fails.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                              ],
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Back to Detector'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const CircularProgressIndicator();
                      }
                      return AspectRatio(
                        aspectRatio: _player.value.aspectRatio > 0
                            ? _player.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(_player),
                      );
                    },
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _player.value.isInitialized ? () {
                  setState(() {
                    if (_player.value.isPlaying) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  });
                } : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play / Pause'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Testing does not publish this link. Some DASH streams may '
                'require Android; DRM-protected streams require a license.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
