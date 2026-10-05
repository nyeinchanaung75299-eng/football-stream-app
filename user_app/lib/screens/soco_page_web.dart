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
      (int _) => html.IFrameElement()
        ..src = _url
        ..allow = 'fullscreen; autoplay'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HtmlElementView(viewType: _viewType),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'open-soco-web',
            tooltip: 'Open Soco in a new tab',
            onPressed: () => html.window.open(_url, '_blank'),
            child: const Icon(Icons.open_in_new_rounded),
          ),
        ),
      ],
    );
  }
}
