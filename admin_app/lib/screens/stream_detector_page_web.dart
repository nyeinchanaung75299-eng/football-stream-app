import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/manual_source_url.dart';
import '../services/stream_detector_service.dart';
import '../services/stream_preview_diagnostics.dart';
import '../services/website_detector_service.dart';
import 'live_links_page.dart';
import 'stream_preview_page.dart';
import 'source_player_page.dart';

/// Web edition: server-side HTML/source scan plus manual direct-link fallback.
/// A web page cannot read cross-origin player network traffic on its own.
class StreamDetectorPage extends StatefulWidget {
  const StreamDetectorPage({super.key});

  @override
  State<StreamDetectorPage> createState() => _StreamDetectorPageState();
}

class _StreamDetectorPageState extends State<StreamDetectorPage> {
  final _website = TextEditingController();
  final _manual = TextEditingController();
  final _referer = TextEditingController();
  final _origin = TextEditingController();
  final _scanner = const WebsiteDetectorService();
  final _detected = <DetectedStream>[];

  String _scanMode = 'browser';
  bool _approved = false;
  bool _scanning = false;
  bool _partialScan = false;
  Map<String, Object?> _diagnostics = const {};
  String? _scanError;
  String? _scanNote;
  String? _manualError;
  String _manualType = 'auto';
  DetectedStream? _manualResult;

  @override
  void dispose() {
    _website.dispose();
    _manual.dispose();
    _referer.dispose();
    _origin.dispose();
    super.dispose();
  }

  Future<void> _scanWebsite() async {
    if (_scanning || !_approved) return;
    final rawUrl = _website.text.trim();
    final target = Uri.tryParse(rawUrl);
    if (target == null ||
        !const {'http', 'https'}.contains(target.scheme.toLowerCase()) ||
        target.host.isEmpty || target.userInfo.isNotEmpty) {
      setState(() => _scanError = 'Enter a full http(s) website URL.');
      return;
    }
    setState(() {
      _scanning = true;
      _scanError = null;
      _scanNote = null;
      _partialScan = false;
      _diagnostics = const {};
      _detected.clear();
    });
    try {
      final result = await _scanner.scan(
        rawUrl, browser: _scanMode == 'browser',
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'Scan did not finish within 30 seconds. Check the network '
          'or switch to HTML Scan. Avoid repeated Browser Run scans '
          'to conserve the Free quota.',
        ),
      );
      if (!mounted) return;
      final seen = <String>{};
      setState(() {
        for (final row in result.links) {
          final url = row['url'] ?? '';
          if (!seen.add(url)) continue;
          _detected.add(DetectedStream(
            url: url,
            type: row['type'] ?? 'auto',
            referer: row['referer'] ?? '',
            origin: row['origin'] ?? '',
          ));
        }
        _scanNote = result.notes;
        _partialScan = result.partial;
        _diagnostics = result.diagnostics;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanError = e.toString().replaceFirst('Bad state: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String? _checkHeader(String text, String name) {
    if (text.trim().isEmpty) return null;
    final uri = Uri.tryParse(text.trim());
    if (text.length > 2048 ||
        text.contains('\n') || text.contains('\r') ||
        uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return name + ' must be an HTTP(S) URL.';
    }
    return null;
  }

  void _checkDirectLink() {
    final raw = _manual.text.trim();
    if (!isValidManualStreamUrl(raw, streamType: _manualType)) {
      setState(() {
        _manualError = 'Enter a direct M3U8/MPD/MP4/FLV link, '
            'or choose a type for an extensionless media URL.';
        _manualResult = null;
      });
      return;
    }
    final error = _checkHeader(_referer.text, 'Referer') ??
        _checkHeader(_origin.text, 'Origin');
    if (error != null) {
      setState(() {
        _manualError = error;
        _manualResult = null;
      });
      return;
    }
    final actual = detectManualStreamType(raw);
    if (_manualType != 'auto' && actual != null && actual != _manualType) {
      setState(() {
        _manualError = 'Stream type does not match the URL extension.';
        _manualResult = null;
      });
      return;
    }
    final type = _manualType == 'auto' ? actual : _manualType;
    if (type == null) {
      setState(() {
        _manualError = 'Select the stream type.';
        _manualResult = null;
      });
      return;
    }
    final referer = _referer.text.trim();
    setState(() {
      _manualError = null;
      _manualResult = DetectedStream(
        url: raw,
        type: type,
        referer: referer,
        origin: _origin.text.trim().isNotEmpty
            ? Uri.parse(_origin.text.trim()).origin
            : referer.isEmpty ? '' : Uri.parse(referer).origin,
      );
    });
  }

  Future<void> _tryRestrictedSourcePlayer(String referer) async {
    if (sourcePlayerPage(referer) == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourcePlayerPage(sourcePage: referer),
      ),
    );
  }

  Future<void> _openSourcePlayer(String referer) async {
    final source = sourcePlayerPage(referer);
    if (source == null) return;
    try {
      final launched = await launchUrl(
        source,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!launched && mounted) {
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

  Widget _streamCard(DetectedStream stream, {bool suggested = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stream.type.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(stream.url),
            if (suggested && stream.referer.isNotEmpty) ...[
              const SizedBox(height: 5),
              const Text(
                'Referer/Origin are suggested from the website, '
                'not captured request headers.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: stream.url),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _test(stream),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Test Stream'),
                ),
                if (sourcePlayerPage(stream.referer) != null) ...[
                  OutlinedButton.icon(
                    key: const Key('try-popup-restricted-player'),
                    onPressed: () => _tryRestrictedSourcePlayer(stream.referer),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Try Pop-up Restricted Player'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openSourcePlayer(stream.referer),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Original Player'),
                  ),
                ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Stream Detector · Web')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text('Website Stream Detector',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text(
                'Enter a website watch-page link. Browser mode observes '
                'media requests during a short, authorized page visit. '
                'HTML mode searches source code without using browser minutes.',
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const Key('website-scan-url'),
                        controller: _website,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Website / Video page URL',
                          hintText: 'https://example.com/watch/video',
                          prefixIcon: Icon(Icons.public),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: const Key('website-scan-mode'),
                        value: _scanMode,
                        decoration: const InputDecoration(
                          labelText: 'Detection mode',
                          prefixIcon: Icon(Icons.radar),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'browser',
                            child: Text('Browser Network Detect (Free quota)'),
                          ),
                          DropdownMenuItem(
                            value: 'html',
                            child: Text('HTML Scan (no browser usage)'),
                          ),
                        ],
                        onChanged: _scanning ? null : (value) {
                          if (value == null) return;
                          setState(() {
                            _scanMode = value;
                            _scanNote = null;
                            _scanError = null;
                            _partialScan = false;
                            _detected.clear();
                          });
                        },
                      ),
                      if (_scanMode == 'browser') ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Uses one short Cloudflare Browser Run session. '
                          'Only works after Free plan and binding are enabled. '
                          'Protected videos, manual login and DRM are not bypassed.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        key: const Key('scan-authorized'),
                        contentPadding: EdgeInsets.zero,
                        value: _approved,
                        onChanged: _scanning ? null : (v) =>
                            setState(() => _approved = v ?? false),
                        title: const Text('I have permission to inspect this page'),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                      if (_scanning && _scanMode == 'browser') ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Checking browser requests. The scan has a '
                          '30-second limit and will show an error if '
                          'the connection stalls.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const Key('scan-website'),
                        onPressed: _approved && !_scanning ? _scanWebsite : null,
                        icon: _scanning
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.radar),
                        label: Text(_scanning ? 'SCANNING WEBSITE...'
                            : _scanMode == 'browser' ? 'DETECT NETWORK STREAMS'
                            : 'SCAN WEBSITE HTML'),
                      ),
                    ],
                  ),
                ),
              ),
              if (_scanError != null) ...[
                const SizedBox(height: 10),
                Text(_scanError!, style: TextStyle(color: colors.error)),
              ],
              if (_scanNote != null && _detected.isEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  key: const Key('scan-needs-browser'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: colors.primary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'No stream URLs detected',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _scanMode == 'browser'
                              ? 'The browser session did not observe M3U8, MPD or MP4 requests.'
                              : _partialScan
                                  ? 'Only part of this large website was scanned.'
                                  : 'No media URL was present in accessible HTML or scripts.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _scanMode == 'browser'
                              ? 'Some players need an explicit Play click, login '
                                'or a licensed DRM session. Browser mode does not '
                                'bypass these requirements.'
                              : 'HTML mode cannot see media requests made after '
                                'video playback. Select Browser Network Detect '
                                'to observe those requests when authorized.',
                        ),
                        if (_scanMode == 'browser' &&
                            _diagnostics.isNotEmpty) ...[
                          const Divider(height: 22),
                          const Text(
                            'Browser inspection details',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Page navigation confirmed: '
                            '${_diagnostics['navigationConfirmed'] == true ? 'Yes' : 'Not confirmed'}',
                          ),
                          Text(
                            'Network requests observed: '
                            '${_diagnostics['requestsObserved'] ?? 'Unknown'}',
                          ),
                          Text(
                            'Network responses observed: '
                            '${_diagnostics['responsesObserved'] ?? 'Unknown'}',
                          ),
                          Text(
                            'HTML5 video elements: '
                            '${_diagnostics['htmlVideoElements'] ?? 'Unknown'}',
                          ),
                          Text(
                            'Iframes on page: '
                            '${_diagnostics['iframeElements'] ?? 'Unknown'}',
                          ),
                          Text(
                            'HTML5 play attempts: '
                            '${_diagnostics['videoPlayAttempts'] ?? 'Unknown'}',
                          ),
                          if (_diagnostics['pageHttpStatus'] != null)
                            Text(
                              'Page HTTP status: ${_diagnostics['pageHttpStatus']}',
                            ),
                          const SizedBox(height: 8),
                          if (_scanNote != null)
                            Text(_scanNote!),
                        ],
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: _website.text.trim()),
                          ),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy website URL'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_scanNote != null && _detected.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_scanNote!),
              ],
              if (_scanNote != null || _detected.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Found streams (${_detected.length})'
                  + (_partialScan ? ' · Partial scan' : ''),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_partialScan) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'This website is large, so only the beginning of its '
                    'HTML/scripts was checked. Some stream links may be missed.',
                  ),
                ],
                for (final stream in _detected)
                  _streamCard(stream, suggested: true),
              ],
              const SizedBox(height: 12),
              const Text(
                'Browser detection observes network URLs; HTML mode scans source '
                'text. Neither mode bypasses authentication or DRM. Only save '
                'streams that you are authorized to distribute.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 14),
              Card(
                child: ExpansionTile(
                  key: const Key('manual-mode-expander'),
                  title: const Text('Manual direct stream link'),
                  subtitle: const Text('Optional: test a known M3U8 / MPD / MP4 URL'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    TextField(
                      key: const Key('web-stream-url'),
                      controller: _manual,
                      minLines: 2,
                      maxLines: 3,
                      onChanged: (_) => setState(() => _manualResult = null),
                      decoration: const InputDecoration(
                        labelText: 'Direct media URL',
                        hintText: 'https://example.com/master.m3u8',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: const Key('web-stream-type'),
                      value: _manualType,
                      decoration: const InputDecoration(labelText: 'Stream type'),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Auto')),
                        DropdownMenuItem(value: 'hls', child: Text('HLS / M3U8')),
                        DropdownMenuItem(value: 'dash', child: Text('DASH / MPD')),
                        DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                        DropdownMenuItem(value: 'flv', child: Text('FLV')),
                      ],
                      onChanged: (value) => setState(() {
                        _manualType = value ?? 'auto';
                        _manualResult = null;
                      }),
                    ),
                    TextField(
                      controller: _referer,
                      decoration: const InputDecoration(
                          labelText: 'Referer (optional)'),
                    ),
                    TextField(
                      controller: _origin,
                      decoration: const InputDecoration(
                          labelText: 'Origin (optional)'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('web-check-stream'),
                      onPressed: _checkDirectLink,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('CHECK LINK'),
                    ),
                    if (_manualError != null)
                      Text(_manualError!,
                          style: TextStyle(color: colors.error)),
                  ],
                ),
              ),
              if (_manualResult != null) ...[
                const SizedBox(height: 12),
                const Text('Ready for testing'),
                _streamCard(_manualResult!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
