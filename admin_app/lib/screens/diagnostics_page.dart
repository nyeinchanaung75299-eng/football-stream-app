import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend_endpoint.dart';
import '../services/diagnostics_service.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final _service = DiagnosticsService();
  final _results = <DiagnosticResult>[];
  bool _running = false;
  DateTime? _checkedAt;
  String? _error;

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _results.clear();
      _checkedAt = DateTime.now().toUtc();
      _error = null;
    });
    try {
      await _service.run(onResult: (result) {
        if (mounted) setState(() => _results.add(result));
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Checks could not finish. Try again.');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copy() async {
    final report = <String, Object?>{
      'version': 1,
      'app': 'admin',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'time': _checkedAt?.toIso8601String(),
      'backendHost': Uri.tryParse(selectedBackend ?? '')?.host,
      'results': _results.map((result) => result.toJson()).toList(),
    };
    try {
      await Clipboard.setData(ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(report)));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Results copied.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not copy results.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed =
        _results.any((result) => result.status == CheckStatus.failed);
    return ListView(
      key: const PageStorageKey('admin-diagnostics'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Text('App & service checks',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          'Check Admin access, the Viewer API and connected services. '
          'To test without VPN, turn it off before running checks.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _run,
              icon: const Icon(Icons.network_check_rounded),
              label: Text(_running ? 'Checking…' : 'Run checks'),
            ),
            OutlinedButton.icon(
              onPressed: _running || _results.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy results'),
            ),
          ],
        ),
        if (_running) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 12),
        if (_error != null) Text(_error!),
        if (!_running && _results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(failed
                ? 'Some app connections need attention.'
                : 'App checks finished. See each service result below.'),
          ),
        if (!_running && _results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Checks run only when you press Run checks. '
                  'No matches, streams or account settings are changed.'),
            ),
          ),
        for (final result in _results) _ResultCard(result: result),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final DiagnosticResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (result.status) {
      CheckStatus.ok => (Icons.check_circle_rounded, Colors.green),
      CheckStatus.warning => (Icons.warning_amber_rounded, Colors.orange),
      CheckStatus.failed => (
          Icons.cancel_rounded,
          Theme.of(context).colorScheme.error
        ),
      CheckStatus.notConfigured => (
          Icons.link_off_rounded,
          Theme.of(context).colorScheme.onSurfaceVariant
        ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: color),
        title: Text(result.title,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
            '${result.detail}${result.ms == null ? '' : ' · ${result.ms} ms'}'),
      ),
    );
  }
}
