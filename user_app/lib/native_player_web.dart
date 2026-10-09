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
  JSString sessionId,
);

@JS('updateFootballPlayerSources')
external void _updateFootballPlayerSources(
  JSString sourcesJson,
  JSString sessionId,
);

class NativePlayer {
  static Future<void> open({
    BuildContext? context,
    required List<Map<String, dynamic>> sources,
    required int selectedIndex,
    String? title,
    String? matchId,
    String? sessionId,
  }) async {
    if (sources.isNotEmpty &&
        selectedIndex >= 0 &&
        selectedIndex < sources.length) {
      final selected = sources[selectedIndex];
      final url = (selected['url'] ?? selected['stream_url'] ?? '')
          .toString()
          .trim();
      final type = (selected['streamType'] ?? selected['stream_type'] ?? 'auto')
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
      (sessionId ?? '').toJS,
    );
  }

  static Future<void> updateSources({
    required List<Map<String, dynamic>> sources,
    required String sessionId,
  }) async {
    _updateFootballPlayerSources(jsonEncode(sources).toJS, sessionId.toJS);
  }
}
