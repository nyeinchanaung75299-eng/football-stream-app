import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

        _webView = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url), headers: headers);
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
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              errorText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_webView != null) {
      return WebViewWidget(controller: _webView!);
    }

    if (_player != null) {
      return BetterPlayer(controller: _player!);
    }

    return const ColoredBox(
      color: Colors.black,
      child: Center(child: CircularProgressIndicator()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watch Live'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black,
            child: SafeArea(
              top: false,
              bottom: false,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _viewer(),
              ),
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
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                    ),
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
                  final mode = item['use_webview'] == true
                      ? 'WEBVIEW'
                      : (item['stream_type'] ?? '').toString().toUpperCase();
                  final resolution = _text(item['resolution']) ??
                      _text(item['label']) ??
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
                        onTap: () => _open(index),
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
                                      .withValues(alpha: isSelected ? .12 : .7),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Icon(
                                  isSelected
                                      ? Icons.play_arrow_rounded
                                      : Icons.dns_rounded,
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
                                      resolution,
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
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.chevron_right_rounded,
                                color: isSelected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
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
