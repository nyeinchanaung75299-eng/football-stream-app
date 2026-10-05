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
        return iframe;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Soco',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Open source in new tab',
            onPressed: () => html.window.open(_url, '_blank'),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: HtmlElementView(viewType: _viewType),
    );
  }
}
