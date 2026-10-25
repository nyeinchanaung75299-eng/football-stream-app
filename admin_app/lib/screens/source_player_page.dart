import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/stream_preview_diagnostics.dart';
import '../widgets/source_player_frame.dart';

/// Optional, user-initiated iframe view with popup/top-level redirects denied.
/// It does not promise ad removal or bypass any website playback restrictions.
class SourcePlayerPage extends StatefulWidget {
  const SourcePlayerPage({super.key, required this.sourcePage});

  final String sourcePage;

  @override
  State<SourcePlayerPage> createState() => _SourcePlayerPageState();
}

class _SourcePlayerPageState extends State<SourcePlayerPage> {
  bool _allowLoad = false;

  Future<void> _openExternally(Uri page) async {
    try {
      final opened = await launchUrl(
        page,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
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

  @override
  Widget build(BuildContext context) {
    final source = sourcePlayerPage(widget.sourcePage);
    return Scaffold(
      appBar: AppBar(title: const Text('Pop-up Restricted Player')),
      body: source == null
          ? const Center(child: Text('Invalid source website URL.'))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Text(
                    source.host,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This view restricts pop-up windows and redirects '
                    'outside the video frame. It does not block every '
                    'in-page advertisement, and some websites may refuse '
                    'embedding or fail to play with these restrictions.',
                  ),
                  const SizedBox(height: 12),
                  if (!_allowLoad)
                    FilledButton.icon(
                      key: const Key('load-sandboxed-player'),
                      onPressed: () => setState(() => _allowLoad = true),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Load Restricted Player'),
                    ),
                  if (_allowLoad)
                    SizedBox(
                      height: 300,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.black),
                        child: SourcePlayerFrame(sourceUrl: source),
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('open-source-browser'),
                    onPressed: () => _openExternally(source),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Browser (Chrome if default)'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'If Chrome is your default browser, the external '
                    'button can open there. Chrome has its own pop-up '
                    'settings, which NCA cannot control. On iPhone, '
                    'Chrome cannot use ordinary desktop ad-block extensions.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
