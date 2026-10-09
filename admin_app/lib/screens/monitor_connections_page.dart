import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/system_monitor_service.dart';

class MonitorConnectionsPage extends StatefulWidget {
  const MonitorConnectionsPage({super.key});
  @override
  State<MonitorConnectionsPage> createState() => _MonitorConnectionsPageState();
}

class _MonitorConnectionsPageState extends State<MonitorConnectionsPage> {
  final _first = TextEditingController(text: '646885');
  final _second = TextEditingController();
  final _secret = TextEditingController();
  final _form = GlobalKey<FormState>();
  String _provider = 'posthog';
  String _region = 'us';
  bool _saving = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _secret.clear();
    _secret.dispose();
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _select(String value) {
    setState(() {
      _provider = value;
      _secret.clear();
      _message = null;
      _first.text = switch (value) {
        'posthog' => '646885',
        'cloudflare' => 'a072aef61b3053983e84755527ef8f39',
        'vercel' => 'nca-network-backup-test',
        _ => '',
      };
      _second.text = switch (value) {
        'cloudflare' => 'football-public-api',
        'vercel' => 'team_ldO4xP4xCfw5N5dSpzfIEgZz',
        _ => '',
      };
    });
  }

  Future<void> _connect() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
      _success = false;
    });
    final config = switch (_provider) {
      'posthog' => {'projectId': _first.text.trim(), 'region': _region},
      'cloudflare' => {
          'accountId': _first.text.trim(),
          'worker': _second.text.trim()
        },
      'vercel' => {
          'project': _first.text.trim(),
          'teamId': _second.text.trim()
        },
      _ => {'folderId': _first.text.trim()},
    };
    try {
      await SystemMonitorService.connect(_provider, config, _secret.text);
      if (mounted) {
        setState(() {
          _success = true;
          _message = 'Read access verified. The encrypted credential is saved '
              'on the server. Return to System Health to view data.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Read access could not be verified. Check the credential, IDs and '
                'read permissions, then return to System Health to check the connection.');
      }
    } finally {
      if (mounted) {
        _secret.clear();
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _guide() async {
    final url = switch (_provider) {
      'posthog' => 'https://posthog.com/docs/api/overview',
      'cloudflare' => 'https://dash.cloudflare.com/profile/api-tokens',
      'vercel' => 'https://vercel.com/account/tokens',
      _ => 'https://developers.google.com/identity/protocols/oauth2/web-server',
    };
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not open setup instructions.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final instructions = switch (_provider) {
      'posthog' =>
        'Create a personal API key scoped to this project with query:read. '
            'Use the US region for the current NCA project. The public phc_ SDK token '
            'cannot read errors. Recording is currently off.',
      'cloudflare' => 'Create a custom read token for this account with '
          'Account → Workers Analytics → Read. This loads invocation metrics. '
          'Detailed HTTP/endpoint logs remain in the Worker dashboard.',
      'vercel' =>
        'Optional: use a token with access to the NCA team and this project. '
            'This connection reads deployment history.',
      _ => 'Optional: paste an OAuth credential JSON containing client_id, '
          'client_secret and refresh_token, authorized to read the archive folder. '
          'The ChatGPT Google Drive connection is separate. Reports can be copied '
          'as JSON/CSV and saved to your folder.',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Connect monitoring services')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text(
                'Only Admin can connect services. Credentials are sent over '
                'HTTPS and encrypted on the server. Saved keys are never returned '
                'to the app or included in APK/Web builds.'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Service'),
                items: const [
                  DropdownMenuItem(value: 'posthog', child: Text('PostHog')),
                  DropdownMenuItem(
                      value: 'cloudflare', child: Text('Cloudflare')),
                  DropdownMenuItem(
                      value: 'vercel', child: Text('Vercel · optional')),
                  DropdownMenuItem(
                      value: 'google-drive',
                      child: Text('Google Drive · optional')),
                ],
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) _select(v);
                      }),
            const SizedBox(height: 16),
            Text(instructions),
            TextButton.icon(
                onPressed: _guide,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open key setup instructions')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _first,
                enabled: !_saving,
                autocorrect: false,
                decoration: InputDecoration(
                    labelText: switch (_provider) {
                  'posthog' => 'Project ID',
                  'cloudflare' => 'Account ID',
                  'vercel' => 'Project name or ID',
                  _ => 'Archive folder ID'
                }),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null),
            if (_provider == 'posthog') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  initialValue: _region,
                  decoration: const InputDecoration(labelText: 'Region'),
                  items: const [
                    DropdownMenuItem(value: 'us', child: Text('US')),
                    DropdownMenuItem(value: 'eu', child: Text('EU'))
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _region = v ?? 'us')),
            ],
            if (_provider == 'cloudflare' || _provider == 'vercel') ...[
              const SizedBox(height: 12),
              TextFormField(
                  controller: _second,
                  enabled: !_saving,
                  autocorrect: false,
                  decoration: InputDecoration(
                      labelText: _provider == 'cloudflare'
                          ? 'Worker name'
                          : 'Team ID'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null),
            ],
            const SizedBox(height: 16),
            TextFormField(
                controller: _secret,
                enabled: !_saving,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [],
                decoration: InputDecoration(
                    labelText: _provider == 'google-drive'
                        ? 'OAuth credential JSON'
                        : 'Read API key',
                    helperText:
                        'Not saved on this device. Cleared after submission.'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: _saving ? null : _connect,
                icon: const Icon(Icons.lock_outline),
                label: Text(
                    _saving ? 'Verifying read access…' : 'Verify & connect')),
            if (_saving)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!,
                      style: TextStyle(
                          color: _success
                              ? Colors.green
                              : Theme.of(context).colorScheme.error))),
          ])),
    );
  }
}
