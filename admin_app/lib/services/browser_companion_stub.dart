import 'package:flutter/material.dart';

// This file is selected on native platforms. The source picker never calls it
// there; native Admin continues using the existing authenticated resolver.
Future<void> showCapture(
  BuildContext context, {
  required String title,
  required String pageUrl,
}) async {}
