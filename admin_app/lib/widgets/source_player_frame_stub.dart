import 'package:flutter/material.dart';

/// Non-web fallback: Android and test runners cannot embed an HTML iframe.
class SourcePlayerFrame extends StatelessWidget {
  const SourcePlayerFrame({super.key, required this.sourceUrl});

  final Uri sourceUrl;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Pop-up-restricted iframe playback is available in NCA Admin Web. '
      'Use Open Original Player on other platforms.',
      textAlign: TextAlign.center,
    ),
  );
}
