import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_off_rounded, size: 44),
              const SizedBox(height: 12),
              const Text(
                'Soco could not be loaded',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
      );
    }

    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_progress < 100)
                  LinearProgressIndicator(
                    value: _progress <= 0 ? null : _progress / 100,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
