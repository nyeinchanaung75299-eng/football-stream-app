import 'dart:async';
import 'package:flutter/material.dart';


// Surface only locally-authored, fixed source error text. Never echo raw
// upstream exceptions, private stream URLs, tokens, or response payloads.
String safeLineLoadError(Object? error) {
  const fallback = 'Could not load lines. Check your connection and try again.';
  if (error is! StateError) return fallback;
  final message = error.message.toString().trim();
  if (!(message.startsWith('TFLIX ') || message.startsWith('TFLIX:') ||
      message.startsWith('StreamCenter ') ||
      message.startsWith('StreamCenter:'))) return fallback;
  if (message.length > 230 ||
      RegExp(r'[\r\n<>]|https?://|Bearer\s|token=|key=', caseSensitive: false)
          .hasMatch(message)) return fallback;
  return message;
}

/// Dismissing the loading dialog cancels opening the chooser. Only remove our
/// own route when the request completes, never the page beneath it.
Future<T?> loadPlayerSources<T>(
  BuildContext context,
  Future<T> Function() load, {
  void Function()? onCancelled,
}) async {
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
  var loadFinished = false;
  unawaited(
    route.popped.then((_) {
      if (!loadFinished) onCancelled?.call();
    }),
  );
  T? result;
  Object? failure;
  var cancelled = false;
  try {
    result = await load();
  } catch (error) {
    failure = error;
  } finally {
    loadFinished = true;
    cancelled = !route.isActive;
    if (route.isActive) navigator.removeRoute(route);
  }
  if (cancelled || !context.mounted) return null;
  if (failure != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(safeLineLoadError(failure))),
    );
    return null;
  }
  return result;
}
