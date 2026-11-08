import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_installer.dart';

/// Admin updates use their own manifest and package, never the Viewer APK.
class AdminUpdateService {
  static bool _checking = false;
  static bool _downloading = false;
  static const _manifestUrls = [
    'https://nyeinchanaung75299-eng.github.io/football-stream-app/releases/admin-latest.json',
    'https://raw.githubusercontent.com/nyeinchanaung75299-eng/football-stream-app/feed/public/releases/admin-latest.json',
  ];
  static const _apkPath = '/nyeinchanaung75299-eng/football-stream-app/feed/public/releases/NCA-admin-arm64-v8a-latest.apk';

  @visibleForTesting
  static bool validAdminRelease(Map<String, dynamic> release) {
    final uri = Uri.tryParse(release['apk_url']?.toString() ?? '');
    final digest = (release['sha256'] ?? '').toString().trim().toLowerCase();
    return release['app'] == 'nca_admin' &&
        release['abi'] == 'arm64-v8a' &&
        uri?.scheme == 'https' &&
        uri?.host == 'raw.githubusercontent.com' &&
        uri?.path == _apkPath &&
        !uri!.hasQuery &&
        !uri.hasFragment &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
  }

  static Future<void> check(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin APK updates are available on Android only.')));
      }
      return;
    }
    if (_checking) return;
    _checking = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;
      Map<String, dynamic>? release;
      final suffix = DateTime.now().millisecondsSinceEpoch;
      for (final url in _manifestUrls) {
        try {
          final response = await http.get(Uri.parse('$url?t=$suffix'),
              headers: const {'Accept': 'application/json'})
              .timeout(const Duration(seconds: 8));
          if (response.statusCode != 200) continue;
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            release = Map<String, dynamic>.from(decoded);
            break;
          }
        } catch (_) { /* Try the alternate public mirror. */ }
      }
      if (!context.mounted) return;
      if (release == null) {
        _notice(context, 'No Admin update is published yet, or the release feed is unavailable.');
        return;
      }
      if (!validAdminRelease(release)) {
        _notice(context, 'Admin update manifest is invalid. No APK was installed.');
        return;
      }
      final nextBuild = int.tryParse(release['build_number']?.toString() ?? '') ?? 0;
      if (nextBuild <= installed) {
        _notice(context, 'NCA Admin is up to date (build ${info.buildNumber}).');
        return;
      }
      final version = (release['version_name'] ?? 'new version').toString();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('NCA Admin $version'),
          content: Text('Admin build $nextBuild is available. '
              'The ARM64 APK will be verified before installation. Update now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Update')),
          ],
        ),
      );
      if (accepted != true || !context.mounted || _downloading) return;
      _downloading = true;
      final progress = ValueNotifier<double>(0);
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context, barrierDismissible: false,
        builder: (_) => PopScope(canPop: false,
          child: AlertDialog(
            title: const Text('Downloading NCA Admin update'),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) => Column(mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value > 0 && value < 1 ? value : null),
                  const SizedBox(height: 10),
                  Text(value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : 'Connecting…'),
                ],
              ),
            ),
          ),
        ),
      );
      unawaited(navigator.push(route));
      try {
        await downloadAndInstallApk(release['apk_url'].toString(),
          expectedSha256: release['sha256'].toString(),
          onProgress: (value) => progress.value = value);
      } catch (_) {
        if (context.mounted) {
          _notice(context, 'Admin APK could not be downloaded or verified. The update was not installed.');
        }
      } finally {
        if (route.isActive) navigator.removeRoute(route);
        progress.dispose();
        _downloading = false;
      }
    } catch (_) {
      if (context.mounted) _notice(context, 'Could not check Admin updates. Try again later.');
    } finally {
      _checking = false;
    }
  }

  static void _notice(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
