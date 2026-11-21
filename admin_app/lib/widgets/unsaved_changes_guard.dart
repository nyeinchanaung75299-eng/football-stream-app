import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FormExitHandle extends ValueNotifier<bool> {
  FormExitHandle() : super(false);
  void savedPop(BuildContext context, [Object? result]) {
    value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && ModalRoute.of(context)?.isCurrent == true)
        Navigator.of(context).pop(result);
    });
  }
}

Future<bool> confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Discard unsaved changes?'),
                content: const Text('Your changes have not been saved.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Discard'))
                ])) ==
    true;

/// Drafts stay in memory only. Sign-out/account change always permits forced
/// private-route closure; a draft confirmation must never retain a session.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard(
      {super.key,
      required this.controllers,
      required this.child,
      this.handle,
      this.dirty,
      this.busy = false});
  final List<TextEditingController> controllers;
  final Widget child;
  final FormExitHandle? handle;
  final bool Function()? dirty;
  final bool busy;
  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  final original = <TextEditingController, String>{};
  String? owner;
  bool bypass = false, asking = false;
  String? user() {
    try {
      return Supabase.instance.client.auth.currentSession?.user.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    owner = user();
    for (final c in widget.controllers) {
      original[c] = c.text;
      c.addListener(changed);
    }
    widget.handle?.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UnsavedChangesGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final c in oldWidget.controllers) {
      if (!widget.controllers.contains(c)) c.removeListener(changed);
    }
    for (final c in widget.controllers) {
      if (!oldWidget.controllers.contains(c)) {
        original[c] = c.text;
        c.addListener(changed);
      }
    }
    if (oldWidget.handle != widget.handle) {
      oldWidget.handle?.removeListener(changed);
      widget.handle?.addListener(changed);
    }
  }

  bool get dirty =>
      (widget.dirty?.call() ?? false) ||
      widget.controllers.any((c) => c.text != original[c]);
  @override
  void dispose() {
    for (final c in widget.controllers) c.removeListener(changed);
    widget.handle?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: bypass ||
          widget.handle?.value == true ||
          owner != user() ||
          (!dirty && !widget.busy),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || asking) return;
        if (widget.busy) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
              content: Text(
                  'Save is still running. Please wait for confirmation.')));
          return;
        }
        asking = true;
        final discard = await confirmDiscard(context);
        asking = false;
        if (!discard || !mounted) return;
        setState(() => bypass = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.isCurrent == true)
            Navigator.pop(context, result);
        });
      },
      child: widget.child);
}
