import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Displays a third-party player in a sandboxed cross-origin iframe.
///
/// This denies new tabs/windows and top-level navigation. It cannot remove
/// in-page advertisements or bypass a source site's iframe/CSP restrictions.
class SourcePlayerFrame extends StatelessWidget {
  const SourcePlayerFrame({super.key, required this.sourceUrl});

  final Uri sourceUrl;

  @override
  Widget build(BuildContext context) {
    // "allow-scripts allow-same-origin" is dangerous for a *same-origin*
    // iframe: it can remove its own sandbox. Only embed an external origin.
    final sameOrigin = sourceUrl.host.toLowerCase() ==
        web.window.location.hostname.toLowerCase();
    if (sameOrigin) {
      return const Center(
        child: Text('For safety, this player only embeds external websites.'),
      );
    }

    return HtmlElementView.fromTagName(
      key: ValueKey(sourceUrl.toString()),
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final frame = element as web.HTMLIFrameElement;
        // Set restrictive permissions BEFORE navigating to the source.
        // In particular, never allow popups or top-level redirects.
        frame.setAttribute(
          'sandbox',
          'allow-scripts allow-same-origin allow-forms allow-presentation',
        );
        frame.setAttribute(
          'allow',
          'autoplay; fullscreen; encrypted-media; picture-in-picture',
        );
        frame.setAttribute('allowfullscreen', '');
        frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
        frame.setAttribute('title', 'Pop-up-restricted source player');
        frame.style.width = '100%';
        frame.style.height = '100%';
        frame.style.border = '0';
        frame.style.backgroundColor = '#000000';
        frame.src = sourceUrl.toString();
      },
    );
  }
}
