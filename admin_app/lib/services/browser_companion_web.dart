import 'dart:async';
import 'dart:convert';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _prefix = 'NCA_ADMIN_CAPTURE_V1:';
const _download =
    'https://nyeinchanaung75299-eng.github.io/football-stream-app/admin/companion-extension.zip';

Future<void> showCapture(
  BuildContext context, {
  required String title,
  required String pageUrl,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CaptureSheet(title: title, pageUrl: pageUrl),
    );

class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet({required this.title, required this.pageUrl});
  final String title;
  final String pageUrl;

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  final _requestId = DateTime.now().microsecondsSinceEpoch.toString();
  final _links = <String, String>{};
  StreamSubscription<html.MessageEvent>? _messages;
  Timer? _handshake;
  Timer? _captureTimeout;
  bool _connected = false;
  bool _started = false;
  String _status = 'Connecting to the PC browser companion…';

  @override
  void initState() {
    super.initState();
    _messages = html.window.onMessage.listen(_receive);
    scheduleMicrotask(() => _send('PING'));
    _handshake = Timer(const Duration(seconds: 2), () {
      if (mounted && !_connected) {
        setState(() => _status =
            'Install the companion extension in desktop Chrome, then reload Admin Web.');
      }
    });
  }

  void _send(String type) {
    html.window.postMessage(
      _prefix +
          jsonEncode({
            'from': 'admin',
            'type': type,
            'requestId': _requestId,
            if (type == 'START') 'url': widget.pageUrl,
          }),
      html.window.location.origin,
    );
  }

  void _receive(html.MessageEvent event) {
    if (event.origin != html.window.location.origin ||
        event.source != html.window ||
        event.data is! String ||
        !(event.data as String).startsWith(_prefix)) return;
    Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(
          jsonDecode((event.data as String).substring(_prefix.length)) as Map);
    } catch (_) {
      return;
    }
    if (message['from'] != 'companion' ||
        message['requestId'] != _requestId ||
        !mounted) return;
    switch (message['type']) {
      case 'READY':
        if (_connected) return;
        _handshake?.cancel();
        setState(() {
          _connected = true;
          _status = 'Opening the original match page…';
        });
        _send('START');
        return;
      case 'STARTED':
        _captureTimeout?.cancel();
        _captureTimeout = Timer(const Duration(minutes: 2), () {
          if (!mounted || !_started) return;
          _send('STOP');
          setState(() {
            _started = false;
            _status = 'Capture timed out. Retry from this page if needed.';
          });
        });
        setState(() {
          _started = true;
          _status = 'Play the video in the new tab, then return here. '
              'This capture stops after two minutes.';
        });
        return;
      case 'LINK':
        final url = message['url']?.toString() ?? '';
        final type = message['format']?.toString() ?? '';
        final parsed = Uri.tryParse(url);
        if (parsed == null ||
            parsed.scheme != 'https' ||
            parsed.host.isEmpty ||
            !const {'hls', 'dash'}.contains(type) ||
            _links.length >= 30) return;
        setState(() {
          _links[url] = type;
          _status = 'Detected links below. Playback is not verified.';
        });
        return;
      case 'STOPPED':
        _captureTimeout?.cancel();
        setState(() {
          _started = false;
          _status = 'Capture stopped. Detected links remain visible here.';
        });
        return;
      case 'ERROR':
        _captureTimeout?.cancel();
        setState(() {
          _started = false;
          _status = message['message']?.toString() ?? 'Capture failed.';
        });
        return;
    }
  }

  @override
  void dispose() {
    if (_started) _send('STOP');
    _handshake?.cancel();
    _captureTimeout?.cancel();
    _messages?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_status),
            const SizedBox(height: 12),
            if (!_connected) ...[
              const Text('One-time setup on PC: download the ZIP, extract it, '
                  'open chrome://extensions, turn on Developer mode, '
                  'choose Load unpacked, and select the extracted folder. '
                  'Reload Admin Web after installing.'),
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(_download),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.download),
                label: const Text('DOWNLOAD PC COMPANION'),
              ),
              TextButton(
                onPressed: () => _send('PING'),
                child: const Text('RETRY CONNECTION'),
              ),
            ] else ...[
              Wrap(spacing: 8, children: [
                if (!_started)
                  OutlinedButton(
                    onPressed: () => _send('START'),
                    child: const Text('OPEN SOURCE & CAPTURE'),
                  ),
                if (_started)
                  OutlinedButton(
                    onPressed: () => _send('STOP'),
                    child: const Text('STOP CAPTURE'),
                  ),
              ]),
              const SizedBox(height: 4),
              const Text('Links are observed on this PC only. No cookies, '
                  'request headers, or DRM keys are collected. A detected '
                  'link may expire or fail to play outside the original site.'),
            ],
            const Divider(),
            Expanded(
              child: _links.isEmpty
                  ? const Center(child: Text('No HLS/DASH links detected yet.'))
                  : ListView(
                      children: [
                        for (final entry in _links.entries)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.value.toUpperCase(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  SelectableText(entry.key),
                                  TextButton.icon(
                                    onPressed: () =>
                                        Clipboard.setData(
                                            ClipboardData(text: entry.key)),
                                    icon: const Icon(Icons.copy),
                                    label: const Text('COPY LINK'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
