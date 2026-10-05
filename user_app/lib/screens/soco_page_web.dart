import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class SocoPage extends StatefulWidget {
  const SocoPage({super.key});

  @override
  State<SocoPage> createState() => _SocoPageState();
}

class _SocoPageState extends State<SocoPage> {
  static int _nextId = 0;
  late final String _viewType;
  static const _url = 'https://m.sutbongtv.com/match.html';

  @override
  void initState() {
    super.initState();
    _viewType = 'soco-match-frame-${_nextId++}';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) {
        final iframe = html.IFrameElement()
          ..src = _url
          ..allow = 'fullscreen; autoplay'
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = '#ffffff';

        // The source is mobile-oriented. Keep it at a phone/tablet-like width
        // instead of stretching the whole third-party page across a desktop.
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: .55),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                    color: Colors.black.withValues(alpha: .08),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: HtmlElementView(viewType: _viewType),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'open-soco-web',
                        tooltip: 'Open Soco source',
                        onPressed: () => html.window.open(_url, '_blank'),
                        child: const Icon(Icons.open_in_new_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
