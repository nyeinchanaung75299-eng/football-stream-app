import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/stream_detector_service.dart';

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
                widget.stream.url,
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
                        return Text(
                          'Playback could not start. The URL may have expired, '
                          'need extra authentication or use an unsupported codec. '
                          'Check the stream rights and format.\n\n'
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
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
                onPressed: () {
                  if (!_player.value.isInitialized) return;
                  setState(() {
                    if (_player.value.isPlaying) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  });
                },
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
