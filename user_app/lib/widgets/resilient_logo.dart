import 'package:flutter/material.dart';
import '../repository_logo.dart';

/// Keep a failed transport from removing a badge which another route serves.
class ResilientLogo extends StatelessWidget {
  const ResilientLogo({
    super.key,
    required this.value,
    required this.fallback,
    this.channelId,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });
  final String value;
  final String? channelId;
  final Widget fallback;
  final double? width, height;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final urls = logoCandidates(value, channelId: channelId);
    Widget imageAt(int index) => index >= urls.length
        ? fallback
        : Image.network(
            urls[index],
            width: width,
            height: height,
            fit: fit,
            filterQuality: FilterQuality.medium,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, __, ___) => imageAt(index + 1),
          );
    return imageAt(0);
  }
}
