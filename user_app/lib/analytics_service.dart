import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class AnalyticsService {
  AnalyticsService._();

  static const _projectToken =
      'phc_quTeE4uCQa8G5MtSoVg6tgYjWULipCWMo8R38RsnijL6';
  static const _host = 'https://us.i.posthog.com';

  static bool _ready = false;

  static Future<void> initialize() async {
    try {
      final config = PostHogConfig(_projectToken);
      config.host = _host;
      config.debug = kDebugMode;
      await Posthog().setup(config);
      _ready = true;
      await capture('app opened', properties: {
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
    } catch (_) {
      // Analytics must never block app startup.
    }
  }

  static Future<void> capture(
    String eventName, {
    Map<String, Object>? properties,
  }) async {
    if (!_ready) return;
    try {
      await Posthog().capture(
        eventName: eventName,
        properties: properties,
      );
    } catch (_) {
      // Analytics is best-effort only.
    }
  }
}
