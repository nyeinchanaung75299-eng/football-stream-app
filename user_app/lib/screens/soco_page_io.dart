import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class SocoPage extends StatefulWidget {
  const SocoPage({super.key});

  @override
  State<SocoPage> createState() => _SocoPageState();
}

class _SocoPageState extends State<SocoPage> {
  static final Uri _source = Uri.parse('https://m.sutbongtv.com/match.html');

  late final WebViewController _controller;
  int _progress = 0;
  String? _error;
  bool _forcedLandscape = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7F9F8))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _error = null);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() => _error = error.description);
            }
          },
        ),
      )
      ..loadRequest(_source);
  }

  Future<void> _toggleOrientation() async {
    if (_forcedLandscape) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) setState(() => _forcedLandscape = false);
      return;
    }

    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) setState(() => _forcedLandscape = true);
  }

  Future<void> _close() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _close();
      },
      child: Scaffold(
        backgroundColor: colors.surfaceContainerLowest,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text(
            'Soco',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: _forcedLandscape ? 'Auto rotate' : 'Landscape',
              onPressed: _toggleOrientation,
              icon: Icon(
                _forcedLandscape
                    ? Icons.screen_lock_rotation_rounded
                    : Icons.screen_rotation_alt_rounded,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public_off_rounded, size: 44),
                      const SizedBox(height: 12),
                      const Text(
                        'Soco could not be loaded',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() => _error = null);
                          _controller.loadRequest(_source);
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('TRY AGAIN'),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: WebViewWidget(controller: _controller),
                  ),
                  if (_progress < 100)
                    Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(
                        value: _progress <= 0 ? null : _progress / 100,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
