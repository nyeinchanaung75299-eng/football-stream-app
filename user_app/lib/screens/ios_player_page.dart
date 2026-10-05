import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../analytics_service.dart';

/// Uses the same player as Safari; Android continues to use Media3.
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
  late final WebViewController _controller;
  bool _started = false;
  bool _closing = false;
  String? _error;

  static const _events = {
    'playback started',
    'playback buffering',
    'playback ended',
    'playback closed',
    'playback line failed',
    'playback auto fallback',
    'playback line selected',
    'playback quality selected',
    'playback needs user interaction',
  };

  @override
  void initState() {
    super.initState();
    _controller = WebViewController.fromPlatformCreationParams(
      WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      ),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setBackgroundColor(Colors.black);
      await _controller.addJavaScriptChannel(
        'NCAPlayerEvents',
        onMessageReceived: _onPlayerEvent,
      );
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            // Only the bundled player can access the native bridge.
            return _isPlayerAsset(request.url) || request.url == 'about:blank'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (url) {
            if (_isPlayerAsset(url)) unawaited(_startPlayer());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _showError();
          },
        ),
      );
      if (!mounted || _closing) return;
      await _controller.loadFlutterAsset('assets/embedded_player.html');
    } catch (_) {
      _showError();
    }
  }

  bool _isPlayerAsset(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'file' &&
        uri.path.endsWith('/assets/embedded_player.html');
  }

  Future<void> _startPlayer() async {
    if (!mounted || _closing || _started) return;
    _started = true;
    try {
      // JSON string literals avoid interpreting provider labels as JavaScript.
      await _controller.runJavaScript('''
        window.posthog = {capture: function(event, properties) {
          NCAPlayerEvents.postMessage(JSON.stringify({event, properties}));
        }};
        window.openFootballPlayer(
          ${jsonEncode(jsonEncode(widget.sources))},
          ${widget.selectedIndex},
          ${jsonEncode(widget.title)},
          ${jsonEncode(widget.matchId)}
        );
      ''');
    } catch (_) {
      _showError();
    }
  }

  void _onPlayerEvent(JavaScriptMessage message) {
    if (!mounted || _closing) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      final event = decoded['event'];
      if (event is! String || !_events.contains(event)) return;
      // Export only known non-sensitive metadata; never bridge URLs or keys.
      final properties = <String, Object>{
        if (widget.matchId.isNotEmpty) 'match_id': widget.matchId,
      };
      final raw = decoded['properties'];
      if (raw is Map) {
        for (final key in [
          'selected_index',
          'from_index',
          'to_index',
          'line_count',
        ]) {
          final value = raw[key];
          if (value is int && value >= 0 && value < 10000) {
            properties[key] = value;
          }
        }
        final type = raw['stream_type'];
        if (const {'auto', 'hls', 'dash', 'flv', 'mp4'}.contains(type)) {
          properties['stream_type'] = type as String;
        }
        for (final key in ['error_code', 'error_category']) {
          final value = raw[key];
          if (value is int && value >= 0 && value < 1000000) {
            properties[key] = value;
          }
        }
        final reason = raw['reason'];
        if (const {
          'line_unavailable',
          'empty_source',
          'unsupported_browser',
          'playback_error',
          'drm_error',
          'startup_timeout',
          'stall_timeout',
          'native_hls_error',
          'native_video_error',
        }.contains(reason)) {
          properties['reason'] = reason as String;
        }
      }
      unawaited(AnalyticsService.capture(event, properties: properties));
      if (event == 'playback closed') {
        _closing = true;
        Navigator.of(context).pop();
      }
    } catch (_) {
      // Invalid bridge messages cannot interrupt playback.
    }
  }

  void _showError() {
    if (!mounted || _closing) return;
    setState(
      () => _error = 'The iPhone player could not be opened. Try again.',
    );
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(
      _controller
          .runJavaScript('''
      document.getElementById('football-player-close')?.click();
    ''')
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error == null
            ? WebViewWidget(controller: _controller)
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.white)),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
