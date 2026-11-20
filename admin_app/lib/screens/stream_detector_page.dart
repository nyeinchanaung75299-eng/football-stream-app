import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/stream_detector_service.dart';
import '../services/hls_detection_session.dart';
import '../services/hls_candidate_verifier.dart';
import 'live_links_page.dart';
import 'stream_preview_page.dart';

/// Browser-based discovery for streams the admin owns or may distribute.
/// WebView is deliberately left in charge of normal page loading. This feature
/// observes requests, but does not read cookies, DRM keys or auth tokens.
class StreamDetectorPage extends StatefulWidget {
  const StreamDetectorPage(
      {super.key,
      this.initialUrl = '',
      this.selectionMode = false,
      this.autoSelectHls = false});
  final String initialUrl;
  final bool selectionMode;

  /// CricHD-only quick flow; other uses of this screen remain unchanged.
  final bool autoSelectHls;

  @override
  State<StreamDetectorPage> createState() => _StreamDetectorPageState();
}

class _StreamDetectorPageState extends State<StreamDetectorPage> {
  final _address = TextEditingController();
  InAppWebViewController? _browser;
  String? _currentPage;
  String? _error;
  int _progress = 0;
  late final HlsDetectionSession _detection;
  List<DetectedStream> get _streams => _detection.streams;
  void _resetDetection({String? page, bool loaded = false}) {
    if (page != null) _currentPage = page;
    _detection.reset(documentLoaded: loaded);
  }

  @override
  void initState() {
    super.initState();
    final verifier = HlsCandidateVerifier();
    _detection = HlsDetectionSession(
      verifier: verifier,
      verify: (stream) async {
        final epoch = _detection.generation;
        final result = await verifier.verify(stream);
        if (mounted && _detection.current(epoch) && result.live)
          await _scanPage();
        return result;
      },
      quickSelect: widget.selectionMode && widget.autoSelectHls,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onSelected: (stream) {
        if (mounted) Navigator.of(context).pop(stream);
      },
    );
    final uri = Uri.tryParse(widget.initialUrl.trim());
    if (uri != null &&
        const {'http', 'https'}.contains(uri.scheme.toLowerCase()) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      _address.text = uri.toString();
    }
  }

  @override
  void dispose() {
    _detection.dispose();
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
    setState(() {
      _error = null;
      _resetDetection(page: uri.toString());
    });
    _browser?.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  void _capture(String rawUrl, [Map<String, String>? headers]) {
    final stream = DetectedStream.fromRequest(
      rawUrl,
      pageUrl: _currentPage,
      headers: headers,
    );
    if (stream == null || !mounted || _currentPage == null) return;
    _detection.observe(stream, headers: headers);
  }

  Future<void> _scanPage() async {
    final browser = _browser;
    final generation = _detection.generation;
    if (browser == null || _currentPage == null) return;
    try {
      // Passive DOM/resource-timing scan for media already loaded by the page.
      // No page fetch/XHR overrides and no user credential extraction.
      final result = await browser.evaluateJavascript(source: r'''
        (() => {
          const urls = new Set(), mediaUrls = new Set();
          const add = (raw) => {
            if (!raw) return;
            try { urls.add(new URL(raw, document.baseURI).href); } catch (_) {}
          };
          document.querySelectorAll('video, video source')
            .forEach(el => { for(const raw of [el.currentSrc,el.src]) {
              add(raw); if(raw)try{mediaUrls.add(new URL(raw,document.baseURI).href)}catch(_){}
            }});
          if (window.performance && performance.getEntriesByType) {
            performance.getEntriesByType('resource')
              .forEach(entry => add(entry.name));
          }
          return {urls:Array.from(urls).slice(0,250), mediaUrls:Array.from(mediaUrls)};
        })()
      ''');
      if (!mounted || generation != _detection.generation) return;
      dynamic decoded = result;
      if (result is String) {
        try {
          decoded = jsonDecode(result);
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is Map && decoded['urls'] is List) {
        final media = decoded['mediaUrls'];
        if (media is List)
          _detection.associateMedia(media.whereType<String>(), generation);
        for (final item in decoded['urls']) {
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
              _resetDetection(page: _currentPage, loaded: _detection.loaded);
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
                        onChanged: (_) {
                          _currentPage = null;
                          _resetDetection();
                        },
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
                      onPressed: () {
                        setState(() => _resetDetection());
                        _browser?.goBack();
                      },
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _resetDetection(page: _currentPage));
                        _browser?.reload();
                      },
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
              onWebViewCreated: (controller) {
                _browser = controller;
                if (_address.text.isNotEmpty) _openAddress();
              },
              onLoadStart: (_, url) {
                final value = url?.toString();
                if (value == null) return;
                setState(() => _resetDetection(page: value));
                _capture(value);
              },
              onProgressChanged: (_, progress) {
                if (mounted) setState(() => _progress = progress);
              },
              // Android: observe resource URLs, returning null means normal
              // loading continues. Other platforms rescan the current document after load.
              shouldInterceptRequest: (_, request) async {
                _capture(request.url.toString(), request.headers);
                return null;
              },
              onLoadStop: (_, url) async {
                if (url?.toString() != _currentPage) return;
                final generation = _detection.generation;
                await _scanPage();
                if (!mounted || generation != _detection.generation) return;
                _detection.documentFinished(generation);
              },
            ),
          ),
          if (widget.autoSelectHls)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
              child: Text(
                _streams.where((stream) => stream.type == 'hls').length > 1
                    ? 'Multiple HLS links found. Choose the correct line below.'
                    : 'Quick detect requires a verified live playlist linked to this page’s video. '
                        'Unverified, finite or ambiguous links remain for manual selection.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                ),
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
                      final check = _detection.checks[item.url];
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
                              if (widget.autoSelectHls && item.type == 'hls')
                                Text(check?.note ?? 'Checking playlist…',
                                    style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 12)),
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
                                  if (item.referer.isNotEmpty ||
                                      item.origin.isNotEmpty)
                                    OutlinedButton.icon(
                                        onPressed: () => Clipboard.setData(
                                            ClipboardData(
                                                text: item.copyDetails)),
                                        icon: const Icon(Icons.copy_all_rounded,
                                            size: 18),
                                        label: const Text('Copy details')),
                                  OutlinedButton.icon(
                                    onPressed: () => _preview(item),
                                    icon:
                                        const Icon(Icons.play_arrow, size: 18),
                                    label: const Text('Test'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => widget.selectionMode
                                        ? Navigator.pop(context, item)
                                        : _useInServer(item),
                                    icon: const Icon(Icons.add_link, size: 18),
                                    label: Text(widget.selectionMode
                                        ? 'USE LINE'
                                        : 'Add to Servers'),
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
