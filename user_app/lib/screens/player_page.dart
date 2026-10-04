import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.links,
  });

  final String title;
  final List<Map<String, dynamic>> links;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  BetterPlayerController? _player;
  WebViewController? _webView;
  int selected = 0;
  String? errorText;

  @override
  void initState() {
    super.initState();
    _open(0);
  }

  String? _text(dynamic value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  Map<String, String> _headers(Map<String, dynamic> item) {
    final result = <String, String>{};
    final referer = _text(item['referer']);
    final origin = _text(item['origin']);
    if (referer != null) result['Referer'] = referer;
    if (origin != null) result['Origin'] = origin;
    return result;
  }

  Future<void> _open(int index) async {
    final item = widget.links[index];
    final useWebView = item['use_webview'] == true;
    final headers = _headers(item);

    _player?.dispose(forceDispose: true);
    _player = null;
    _webView = null;
    errorText = null;
    selected = index;

    try {
      if (useWebView) {
        final url = _text(item['webview_url']);
        if (url == null) throw Exception('WebView URL is empty.');

        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url), headers: headers);
        _webView = controller;
      } else {
        final url = _text(item['stream_url']);
        if (url == null) throw Exception('Stream URL is empty.');

        DrmConfiguration? drm;
        final kid = _text(item['key_id']);
        final key = _text(item['key_data']);

        if (kid != null || key != null) {
          if (kid == null || key == null) {
            throw Exception('Both keyID and keyData are required for ClearKey.');
          }
          final clearKey = BetterPlayerClearKeyUtils.generateKey({kid: key});
          drm = DrmConfiguration(
            drmType: DrmType.clearKey,
            clearKey: clearKey,
          );
        }

        final dataSource = PlayerDataSource.network(
          url,
          liveStream: true,
          headers: headers,
          videoFormat: (item['stream_type'] == 'dash')
              ? VideoFormat.dash
              : VideoFormat.hls,
          drmConfiguration: drm,
          notificationConfiguration: NotificationConfiguration(
            showNotification: item['send_notification'] == true,
            title: widget.title,
            author: 'Football Live',
          ),
        );

        _player = BetterPlayerController(
          const PlayerConfiguration(
            autoPlay: true,
            aspectRatio: 16 / 9,
            fit: BoxFit.contain,
            allowedScreenSleep: false,
          ),
          betterPlayerDataSource: dataSource,
        );
      }
    } catch (e) {
      errorText = e.toString();
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.dispose(forceDispose: true);
    super.dispose();
  }

  Widget _viewer() {
    if (errorText != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Text(
          errorText!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    if (_webView != null) {
      return WebViewWidget(controller: _webView!);
    }
    if (_player != null) {
      return BetterPlayer(controller: _player!);
    }
    return const Center(child: CircularProgressIndicator());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: MediaQuery.of(context).size.width * 9 / 16,
            child: _viewer(),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: widget.links.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = widget.links[index];
                final mode = item['use_webview'] == true
                    ? 'WEBVIEW'
                    : (item['stream_type'] ?? '').toString().toUpperCase();
                final resolution = _text(item['resolution']) ??
                    _text(item['label']) ??
                    'Server ${index + 1}';
                final hasKey = _text(item['key_id']) != null &&
                    _text(item['key_data']) != null;

                return ListTile(
                  leading: Icon(
                    selected == index
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(resolution),
                  subtitle: Text('$mode${hasKey ? ' • ClearKey' : ''}'),
                  onTap: () => _open(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
