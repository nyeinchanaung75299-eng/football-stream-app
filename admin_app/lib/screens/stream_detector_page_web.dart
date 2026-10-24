import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/manual_source_url.dart';
import '../services/stream_detector_service.dart';
import 'live_links_page.dart';
import 'stream_preview_page.dart';

/// Browser-safe Stream Detector mode.
///
/// Browsers cannot intercept another site's cross-origin video requests.
/// Admins can paste authorized direct media URLs, preview where browser codecs
/// and CORS allow, and hand them to the existing Stream Servers form.
class StreamDetectorPage extends StatefulWidget {
  const StreamDetectorPage({super.key});

  @override
  State<StreamDetectorPage> createState() => _StreamDetectorPageState();
}

class _StreamDetectorPageState extends State<StreamDetectorPage> {
  final _url = TextEditingController();
  final _referer = TextEditingController();
  final _origin = TextEditingController();
  String _chosenType = 'auto';
  String? _error;
  DetectedStream? _result;

  @override
  void dispose() {
    _url.dispose();
    _referer.dispose();
    _origin.dispose();
    super.dispose();
  }

  void _invalidate() {
    if (_result == null && _error == null) return;
    setState(() {
      _result = null;
      _error = null;
    });
  }

  String? _validHeader(String value, String label) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (text.contains('\n') ||
        text.contains('\r') ||
        text.length > 2048 ||
        uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return '$label must be a valid HTTP(S) URL.';
    }
    return null;
  }

  void _inspect() {
    final url = _url.text.trim();
    if (!isValidManualStreamUrl(url, streamType: _chosenType)) {
      setState(() {
        _error = 'Enter a direct HTTP(S) media URL. For URLs without a known '
            'file extension, select the stream format.';
        _result = null;
      });
      return;
    }
    final refererError = _validHeader(_referer.text, 'Referer');
    final originError = _validHeader(_origin.text, 'Origin');
    final error = refererError ?? originError;
    if (error != null) {
      setState(() {
        _error = error;
        _result = null;
      });
      return;
    }

    final detectedType = detectManualStreamType(url);
    final effectiveType = _chosenType == 'auto'
        ? detectedType
        : _chosenType;
    if (effectiveType == null) {
      setState(() {
        _error = 'Choose the stream type (HLS, DASH, MP4 or FLV).';
        _result = null;
      });
      return;
    }

    final fromUrl = Uri.parse(url);
    final referer = _referer.text.trim();
    final origin = _origin.text.trim();
    final fallbackOrigin = referer.isEmpty ? '' : Uri.parse(referer).origin;
    setState(() {
      _error = null;
      _result = DetectedStream(
        url: fromUrl.toString(),
        type: effectiveType,
        referer: referer,
        origin: origin.isEmpty ? fallbackOrigin : Uri.parse(origin).origin,
      );
    });
  }

  void _copy(DetectedStream stream) {
    Clipboard.setData(ClipboardData(text: stream.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stream URL copied.')),
    );
  }

  Future<void> _test(DetectedStream stream) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StreamPreviewPage(stream: stream),
      ),
    );
  }

  Future<void> _add(DetectedStream stream) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveLinksPage(
          initialStreamUrl: stream.url,
          initialReferer: stream.referer,
          initialOrigin: stream.origin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stream = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Stream Detector · Web')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
            children: [
              Text(
                'Web Stream Tester',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Paste a direct link from a video source you are authorized '
                'to use. Browser security prevents this web app from '
                'automatically intercepting another website\'s requests. '
                'Use the Android Admin app for automatic request detection.',
              ),
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('web-stream-url'),
                        controller: _url,
                        onChanged: (_) => _invalidate(),
                        minLines: 2,
                        maxLines: 4,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Direct stream URL',
                          hintText: 'https://example.com/live/master.m3u8',
                          helperText: 'M3U8 / MPD / MP4 / FLV; not a watch page',
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: const Key('web-stream-type'),
                        value: _chosenType,
                        decoration: const InputDecoration(
                          labelText: 'Stream type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text('Auto (by URL extension)'),
                          ),
                          DropdownMenuItem(value: 'hls', child: Text('HLS / M3U8')),
                          DropdownMenuItem(value: 'dash', child: Text('DASH / MPD')),
                          DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                          DropdownMenuItem(value: 'flv', child: Text('FLV')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _chosenType = value;
                            _result = null;
                            _error = null;
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Optional playback headers'),
                        subtitle: const Text(
                          'Referer / Origin only. Do not paste cookies or '
                          'access tokens into header fields.',
                        ),
                        children: [
                          TextField(
                            controller: _referer,
                            onChanged: (_) => _invalidate(),
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Referer (optional)',
                              hintText: 'https://example.com/watch',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _origin,
                            onChanged: (_) => _invalidate(),
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'Origin (optional)',
                              hintText: 'https://example.com',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        key: const Key('web-check-stream'),
                        onPressed: _inspect,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('CHECK LINK'),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (stream != null) ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.movie_filter_outlined),
                            const SizedBox(width: 8),
                            Text(
                              'Ready for testing · ${stream.type.toUpperCase()}',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(stream.url),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _copy(stream),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _test(stream),
                              icon: const Icon(Icons.play_circle),
                              label: const Text('Test Stream'),
                            ),
                            FilledButton.icon(
                              onPressed: () => _add(stream),
                              icon: const Icon(Icons.add_link),
                              label: const Text('Add to Servers'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'CHECK LINK validates the URL format; it does not verify '
                'playback. Test Stream opens an actual preview. '
                'Web playback depends on CORS, codecs, token expiry and '
                'browser support. Referer/Origin cannot be forced by a browser '
                'player. DRM-protected video requires proper licensing.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
