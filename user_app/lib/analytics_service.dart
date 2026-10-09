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
      config.captureApplicationLifecycleEvents = true;
      config.surveys = false;
      config.sessionReplay = false;
      config.errorTrackingConfig.captureFlutterErrors = true;
      config.errorTrackingConfig.capturePlatformDispatcherErrors = true;
      await Posthog().setup(config).timeout(const Duration(seconds: 3));
      _ready = true;
      // Super-properties also tag automatic exception events. Custom capture
      // properties alone only tagged our explicit events, leaving crashes
      // without an Admin/Viewer or Web/native breakdown.
      await Future.wait([
        Posthog().register('app', 'nca_viewer'),
        Posthog().register(
          'platform',
          kIsWeb ? 'web' : defaultTargetPlatform.name,
        ),
      ]).timeout(const Duration(seconds: 1));
      await capture('app opened');
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
      await Posthog()
          .capture(
            eventName: eventName,
            properties: <String, Object>{
              'app': 'nca_viewer',
              'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
              ...?properties,
            },
          )
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      // Analytics is best-effort only.
    }
  }
}
