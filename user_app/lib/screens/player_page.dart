import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
  late final Player player;
  late final VideoController controller;
  int selected = 0;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    open(0);
  }

  Future<void> open(int index) async {
    selected = index;
    final item = widget.links[index];
    await player.open(Media(item['stream_url'] as String));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: controller),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: widget.links.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = widget.links[index];
                return ListTile(
                  leading: Icon(
                    selected == index
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(item['label'] ?? 'Stream ${index + 1}'),
                  subtitle:
                      Text((item['stream_type'] ?? '').toString().toUpperCase()),
                  onTap: () => open(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
