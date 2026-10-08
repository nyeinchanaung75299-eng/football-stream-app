import 'dart:async';
import 'package:flutter/material.dart';

/// Dismissing the loading dialog cancels opening the chooser. Only remove our
/// own route when the request completes, never the page beneath it.
Future<T?> loadPlayerSources<T>(
  BuildContext context,
  Future<T> Function() load,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      content: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 16),
          Flexible(child: Text('Loading lines…')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  unawaited(navigator.push(route));
  T? result;
  var failed = false;
  var cancelled = false;
  try {
    result = await load();
  } catch (_) {
    failed = true;
  } finally {
    cancelled = !route.isActive;
    if (route.isActive) navigator.removeRoute(route);
  }
  if (cancelled || !context.mounted) return null;
  if (failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not load lines. Check your connection and try again.',
        ),
      ),
    );
    return null;
  }
  return result;
}
