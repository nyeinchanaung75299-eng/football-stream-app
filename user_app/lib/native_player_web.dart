import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('window.location.assign')
external void _navigateTopLevel(JSString url);

@JS('openFootballPlayer')
external void _openFootballPlayer(
  JSString sourcesJson,
  JSNumber selectedIndex,
  JSString title,
  JSString matchId,
);

class NativePlayer {
  static Future<void> open({
    BuildContext? context,
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
    String? matchId,
  }) async {
    if (sources.isNotEmpty &&
        selectedIndex >= 0 &&
        selectedIndex < sources.length) {
      final selected = sources[selectedIndex];
      final url = (selected['url'] ?? selected['stream_url'] ?? '')
          .toString()
          .trim();
      final type =
          (selected['streamType'] ?? selected['stream_type'] ?? 'auto')
              .toString()
              .toLowerCase();

      // GitHub Pages is HTTPS, so an HTTP HLS line cannot be embedded as a
      // mixed-content subresource. A top-level navigation lets Safari hand
      // the .m3u8 URL to its native HLS player instead.
      if (url.toLowerCase().startsWith('http://') &&
          (type == 'hls' ||
              type == 'm3u8' ||
              url.toLowerCase().contains('.m3u8'))) {
        final sourcePage = (selected['referer'] ?? '').toString().trim();

        // Directly opening the raw Fawa HLS endpoint loses the Referer/Origin
        // context and nginx returns 403. Open the source match page instead;
        // that page then loads its HLS stream with the headers it expects.
        if (sourcePage.startsWith('http://') ||
            sourcePage.startsWith('https://')) {
          _navigateTopLevel(sourcePage.toJS);
        } else {
          _navigateTopLevel(url.toJS);
        }
        return;
      }
    }

    _openFootballPlayer(
      jsonEncode(sources).toJS,
      selectedIndex.toJS,
      (title ?? 'Football Live').toJS,
      (matchId ?? '').toJS,
    );
  }
}
