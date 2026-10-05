import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../native_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.links,
  });

  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> links;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  WebViewController? _webView;
  int? selected;
  String? errorText;

  String? _text(dynamic value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  Map<String, String> _headers(Map<String, dynamic> item) {
    final headers = <String, String>{};
    final referer = _text(item['referer']);
    final origin = _text(item['origin']);
    if (referer != null) headers['Referer'] = referer;
    if (origin != null) headers['Origin'] = origin;
    return headers;
  }

  Future<void> _play(int index) async {
    final item = widget.links[index];
    final useWebView = item['use_webview'] == true;

    setState(() {
      selected = index;
      errorText = null;
      _webView = null;
    });

    try {
      if (useWebView) {
        final url = _text(item['webview_url']);
        if (url == null) throw Exception('WebView URL is empty.');

        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black)
          ..loadRequest(
            Uri.parse(url),
            headers: _headers(item),
          );

        if (!mounted) return;
        setState(() => _webView = controller);
        return;
      }

      final nativeSources = widget.links
          .where((x) => x['use_webview'] != true)
          .map(
            (x) => <String, dynamic>{
              'id': x['id']?.toString(),
              'resolution':
                  _text(x['resolution']) ?? _text(x['label']) ?? 'Auto',
              'streamType': (x['stream_type'] ?? 'auto').toString(),
              'url': _text(x['stream_url']) ?? '',
              'referer': _text(x['referer']) ?? '',
              'origin': _text(x['origin']) ?? '',
              'keyId': _text(x['key_id']) ?? '',
              'keyData': _text(x['key_data']) ?? '',
            },
          )
          .where((x) => (x['url'] as String).isNotEmpty)
          .toList();

      final selectedId = item['id']?.toString();
      var nativeIndex = nativeSources.indexWhere(
        (x) => x['id']?.toString() == selectedId,
      );
      if (nativeIndex < 0) nativeIndex = 0;

      if (nativeSources.isEmpty) {
        throw Exception('No playable native stream.');
      }

      if (!mounted) return;
      await NativePlayer.open(
        context: context,
        sources: nativeSources,
        selectedIndex: nativeIndex,
        title: widget.title,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorText = 'This server could not be opened.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Watch Live')),
      body: Column(
        children: [
          if (_webView != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: WebViewWidget(controller: _webView!),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 28,
              ),
              color: Colors.black,
              child: Column(
                children: [
                  Icon(
                    errorText == null
                        ? Icons.play_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: errorText == null
                        ? Colors.white70
                        : Colors.redAccent.shade100,
                    size: 54,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    errorText ??
                        'Choose a server. For HLS/MPD adaptive streams, the player reads all qualities from that one link automatically.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: errorText == null
                          ? Colors.white70
                          : Colors.redAccent.shade100,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Servers',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.links.length} available',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...List.generate(widget.links.length, (index) {
                  final item = widget.links[index];
                  final isSelected = selected == index;
                  final isWeb = item['use_webview'] == true;
                  final mode = isWeb
                      ? 'WEBVIEW'
                      : (item['stream_type'] ?? 'AUTO')
                          .toString()
                          .toUpperCase();
                  final res = _text(item['label']) ??
                      _text(item['resolution']) ??
                      'Server ${index + 1}';
                  final hasKey = _text(item['key_id']) != null &&
                      _text(item['key_data']) != null;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(19),
                        side: BorderSide(
                          color: isSelected
                              ? colors.primary
                              : colors.outlineVariant.withValues(alpha: .55),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(19),
                        onTap: () => _play(index),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: (isSelected
                                          ? colors.primary
                                          : colors.surfaceContainerHighest)
                                      .withValues(
                                    alpha: isSelected ? .12 : .7,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  isSelected
                                      ? Icons.play_arrow_rounded
                                      : Icons.hd_rounded,
                                  color: isSelected
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      res,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$mode${hasKey ? ' • ClearKey' : ''}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
