import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Shows the runtime-reported app version, not a hard-coded release number.
/// Release APK build numbers differ from pubspec due to split ABI offsets.
class AdminVersionDialog extends StatelessWidget {
  const AdminVersionDialog({
    super.key,
    required this.version,
    required this.buildNumber,
    this.isWeb = false,
  });

  final String version;
  final String buildNumber;
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('NCA Admin · App Version'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isWeb ? 'Web version: $version' : 'Installed version: $version'),
          const SizedBox(height: 8),
          Text('Build number: $buildNumber'),
          const SizedBox(height: 10),
          Text(
            'Admin updates are separate from Viewer updates.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

Future<void> showAdminVersionDialog(BuildContext context) async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AdminVersionDialog(
        version: info.version,
        buildNumber: info.buildNumber,
        isWeb: kIsWeb,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read this installation\'s version.'),
        ),
      );
    }
  }
}
