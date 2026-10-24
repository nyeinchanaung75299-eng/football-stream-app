import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/stream_detector_service.dart';
import 'live_links_page.dart';
import 'stream_preview_page.dart';

/// Browser-based discovery for streams the admin owns or may distribute.
/// WebView is deliberately left in charge of normal page loading. This feature
/// observes requests, but does not read cookies, DRM keys or auth tokens.
class StreamDetectorPage extends StatefulWidget {
  const StreamDetectorPage({super.key});

  @override
  State<StreamDetectorPage> createState() => _StreamDetectorPageState();
}

class _StreamDetectorPageState extends State<StreamDetectorPage> {
  final _address = TextEditingController();
  final _streams = <DetectedStream>[];
  final _seenUrls = <String>{};
  InAppWebViewController? _browser;
  String? _currentPage;
  String? _error;
  int _progress = 0;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _openAddress() {
    var value = _address.text.trim();
    if (value.isEmpty) return;
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      setState(() => _error = 'Enter a valid http(s) website URL.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    _browser?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  void _capture(String rawUrl, [Map<String, String>? headers]) {
    final stream = DetectedStream.fromRequest(
      rawUrl,
      pageUrl: _currentPage,
      headers: headers,
    );
    if (stream == null || !mounted || _seenUrls.contains(stream.url)) return;
    if (_streams.length >= 100) return;
    setState(() {
      _seenUrls.add(stream.url);
      _streams.insert(0, stream);
    });
  }

  Future<void> _scanPage() async {
    final browser = _browser;
    if (browser == null) return;
    try {
      // Passive DOM/resource-timing scan for media already loaded by the page.
      // No page fetch/XHR overrides and no user credential extraction.
      final result = await browser.evaluateJavascript(source: r'''
        (() => {
          const urls = new Set();
          const add = (raw) => {
            if (!raw) return;
            try { urls.add(new URL(raw, document.baseURI).href); } catch (_) {}
          };
          document.querySelectorAll('video, video source, audio, audio source')
            .forEach(el => { add(el.currentSrc); add(el.src); });
          if (window.performance && performance.getEntriesByType) {
            performance.getEntriesByType('resource')
              .forEach(entry => add(entry.name));
          }
          return Array.from(urls).slice(0, 250);
        })()
      ''');
      dynamic decoded = result;
      if (result is String) {
        try {
          decoded = jsonDecode(result);
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is List) {
        for (final item in decoded) {
          if (item is String) _capture(item);
        }
      }
    } catch (_) {
      // The native Android request observer still works when page JS is denied.
    }
  }

  Future<void> _preview(DetectedStream item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StreamPreviewPage(stream: item),
      ),
    );
  }

  Future<void> _useInServer(DetectedStream item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveLinksPage(
          initialStreamUrl: item.url,
          initialReferer: item.referer,
          initialOrigin: item.origin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Detector'),
        actions: [
          IconButton(
            tooltip: 'Clear detected streams',
            onPressed: () => setState(() {
              _streams.clear();
              _seenUrls.clear();
            }),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _address,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _openAddress(),
                        decoration: const InputDecoration(
                          labelText: 'Website URL',
                          hintText: 'https://example.com/watch',
                          isDense: true,
                          prefixIcon: Icon(Icons.public),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _openAddress,
                      child: const Text('GO'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _browser?.goBack(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                    TextButton.icon(
                      onPressed: () => _browser?.reload(),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reload'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _scanPage,
                      icon: const Icon(Icons.radar, size: 18),
                      label: const Text('Rescan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          SizedBox(
            height: 280,
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('about:blank')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useOnLoadResource: true,
                useShouldInterceptRequest: true,
                mediaPlaybackRequiresUserGesture: true,
                allowsInlineMediaPlayback: true,
              ),
              onWebViewCreated: (controller) => _browser = controller,
              onLoadStart: (_, url) {
                final value = url?.toString();
                if (value == null) return;
                _capture(value);
                final uri = Uri.tryParse(value);
                if (uri != null &&
                    const {'https', 'http'}.contains(uri.scheme.toLowerCase())) {
                  _currentPage = value;
                }
              },
              onProgressChanged: (_, progress) {
                if (mounted) setState(() => _progress = progress);
              },
              onLoadResource: (_, resource) =>
                  _capture(resource.url?.toString() ?? ''),
              // Android: observe resource URLs, returning null means normal
              // loading continues. Unsupported platforms rely on onLoadResource.
              shouldInterceptRequest: (_, request) async {
                _capture(request.url.toString(), request.headers);
                return null;
              },
              onLoadStop: (_, __) => _scanPage(),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  'Detected streams (${_streams.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  'Play video above',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: _streams.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Open a website and play an authorized video. '
                        'M3U8, MPD, MP4 and FLV requests will appear here. '
                        'On iOS some network requests are not visible.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _streams.length,
                    itemBuilder: (context, index) {
                      final item = _streams[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.play_circle_outline),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.type.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                item.url,
                                maxLines: 2,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(text: item.url),
                                    ),
                                    icon: const Icon(Icons.copy, size: 18),
                                    label: const Text('Copy'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _preview(item),
                                    icon: const Icon(Icons.play_arrow, size: 18),
                                    label: const Text('Test'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _useInServer(item),
                                    icon: const Icon(Icons.add_link, size: 18),
                                    label: const Text('Add to Servers'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
