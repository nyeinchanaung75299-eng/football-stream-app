import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_installer.dart';

class AppUpdateService {
  AppUpdateService._();

  static bool _checked = false;

  static const _manifestUrls = <String>[
    'https://nyeinchanaung75299-eng.github.io/'
        'football-stream-app/releases/latest.json',
    'https://raw.githubusercontent.com/'
        'nyeinchanaung75299-eng/football-stream-app/'
        'feed/public/releases/latest.json',
  ];

  static Future<void> check(
    BuildContext context, {
    bool force = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_checked && !force) return;
    _checked = true;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      final stamp = DateTime.now().millisecondsSinceEpoch;
      Map<dynamic, dynamic>? data;

      for (final base in _manifestUrls) {
        try {
          final response = await http
              .get(
                Uri.parse('$base?t=$stamp'),
                headers: const {
                  'Accept': 'application/json',
                  'Cache-Control': 'no-cache',
                },
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode < 200 || response.statusCode >= 300) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            data = decoded;
            break;
          }
        } catch (_) {}
      }

      if (data == null) {
        if (force && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not check for updates right now.'),
            ),
          );
        }
        return;
      }

      final latestBuild =
          int.tryParse(data['build_number']?.toString() ?? '') ?? 0;
      if (latestBuild <= currentBuild) {
        if (force && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NCA is already up to date.'),
            ),
          );
        }
        return;
      }

      final version =
          data['version_name']?.toString().trim().isNotEmpty == true
              ? data['version_name'].toString()
              : 'new version';
      final apkUrl = data['apk_url']?.toString().trim() ?? '';
      final notes = data['notes']?.toString().trim() ?? '';
      final mandatory = data['mandatory'] == true;
      if (apkUrl.isEmpty || !context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt_rounded),
          title: Text('NCA $version available'),
          content: Text(
            notes.isEmpty
                ? 'A newer version of NCA is ready. Update now?'
                : notes,
          ),
          actions: [
            if (!mandatory)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _download(context, apkUrl);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Update now'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Update checking must never block the app.
      if (force && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not check for updates right now.'),
          ),
        );
      }
    }
  }

  static Future<void> _download(
    BuildContext context,
    String apkUrl,
  ) async {
    final progress = ValueNotifier<double>(0);

    if (context.mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => AlertDialog(
            title: const Text('Downloading NCA update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: value > 0 && value < 1 ? value : null,
                ),
                const SizedBox(height: 12),
                Text(
                  value > 0
                      ? '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%'
                      : 'Starting download…',
                ),
              ],
            ),
          ),
        ),
      );
    }

    try {
      await downloadAndInstallApk(
        apkUrl,
        onProgress: (value) => progress.value = value,
      );
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update download failed. Please check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      progress.dispose();
    }
  }
}
