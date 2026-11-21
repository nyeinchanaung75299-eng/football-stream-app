import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/line_share_payload.dart';

Future<void> showLineShareSheet(
        BuildContext context, LineSharePayload payload) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => LineShareSheet(payload: payload));

class LineShareSheet extends StatefulWidget {
  const LineShareSheet({super.key, required this.payload});
  final LineSharePayload payload;
  @override
  State<LineShareSheet> createState() => _LineShareSheetState();
}

class _LineShareSheetState extends State<LineShareSheet> {
  bool working = false;
  String? error;
  bool copied = false;

  Rect _anchor() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export() async {
    if (working) return;
    setState(() {
      working = true;
      error = null;
    });
    try {
      // Private cache/FileProvider on Android; Web Share where supported,
      // browser download otherwise. No storage/media permission is required.
      final result = await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(Uint8List.fromList(utf8.encode(widget.payload.text)),
              mimeType: 'text/plain')
        ],
        fileNameOverrides: [widget.payload.filename],
        title: widget.payload.matchName,
        sharePositionOrigin: _anchor(),
      ));
      // Browsers cannot report the selected target or whether the user sent.
      if (!kIsWeb &&
          mounted &&
          result.status == ShareResultStatus.unavailable) {
        setState(() =>
            error = 'File sharing is unavailable here. Use Copy all below.');
      }
    } catch (_) {
      if (mounted)
        setState(() => error = 'Could not share the file. Use Copy all below.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _telegram() async {
    if (working) return;
    final uri = widget.payload.telegramUri;
    if (uri == null) return _export();
    // Call directly from the tap before any await, preserving the browser's
    // user activation. Telegram chooses the chat; no bot sends on our behalf.
    setState(() {
      working = true;
      error = null;
    });
    try {
      final opened = await launchUrl(uri,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
          webOnlyWindowName: '_blank');
      if (!opened && mounted)
        setState(() =>
            error = 'Could not open Telegram. Use Copy all or Export .txt.');
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Could not open Telegram. Use Copy all or Export .txt.');
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
          child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                widget.payload.lines.length == 1
                    ? 'Share line'
                    : 'Share all lines',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(widget.payload.matchName),
            const SizedBox(height: 12),
            Flexible(
                child: SingleChildScrollView(
                    child: SelectableText(widget.payload.text))),
            const SizedBox(height: 12),
            Text(widget.payload.telegramUri == null
                ? 'Long details will be shared as a .txt file. Choose Telegram in the share sheet.'
                : 'Choose a Telegram chat, then tap Send.'),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: working ? null : _telegram,
                icon: const Icon(Icons.send),
                label: const Text('Share to Telegram')),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                              ClipboardData(text: widget.payload.text));
                          if (mounted)
                            setState(() {
                              error = null;
                              copied = true;
                            });
                        } catch (_) {
                          if (mounted)
                            setState(() => error =
                                'Select the preview text above to copy it manually.');
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(copied ? 'Copied ✓' : 'Copy all'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: working ? null : _export,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Export .txt'))),
            ]),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
          ],
        ),
      ));
}
