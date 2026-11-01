import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../network_endpoints.dart';

/// Registers both Telegram webhooks from already configured Supabase secrets.
/// No BotFather token or Telegram secret ever reaches the Admin browser.
class TelegramSetupPage extends StatefulWidget {
  const TelegramSetupPage({super.key});

  @override
  State<TelegramSetupPage> createState() => _TelegramSetupPageState();
}

class _TelegramSetupPageState extends State<TelegramSetupPage> {
  bool connecting = false;
  String? result;
  bool connected = false;

  Future<void> connect() async {
    if (connecting) return;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => result = 'Admin session expired. Please sign in again.');
      return;
    }
    setState(() {
      connecting = true;
      result = null;
      connected = false;
    });
    try {
      final response = await http.post(
        Uri.parse('$vercelBackupBase/functions/v1/telegram-connect'),
        headers: {
          'Authorization': 'Bearer $token',
          'apikey': const String.fromEnvironment(
            'SUPABASE_PUBLISHABLE_KEY',
            defaultValue: 'sb_publishable_ka-rZxHdJUMYng6WJDDQUg_ZcWZJl3O',
          ),
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: '{}',
      ).timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Unexpected connection status');
      }
      final ok = response.statusCode == 200 && data['connected'] == true;
      if (!mounted) return;
      setState(() {
        connected = ok;
        result = ok
            ? 'Viewer and Private Admin webhooks are connected. '
                'Send /start to Viewer, then /whoami to Private Admin.'
            : (data['error']?.toString() ??
                'Could not connect both Telegram bots. '
                    'Check that all four Supabase secrets were saved.');
      });
    } catch (_) {
      if (mounted) {
        setState(() => result =
            'Unable to register Telegram webhooks. Check the network and try again.');
      }
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Telegram Bots')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Connect NCA Telegram Bots',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            const ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Viewer Bot'),
              subtitle: Text('@NCAFootballViewer_bot'),
            ),
            const ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Private Admin Bot'),
              subtitle: Text('@NCAPrivate_bot'),
            ),
            const SizedBox(height: 12),
            const Text(
              'After saving four private Edge Function secrets in Supabase, '
              'connect the webhooks here. Bot tokens and secrets stay in Supabase.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: connecting ? null : connect,
              icon: connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded),
              label: Text(connecting ? 'CONNECTING…' : 'CONNECT TELEGRAM BOTS'),
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              Text(result!,
                  style: TextStyle(
                      color: connected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            const Text('After connecting:'),
            const SizedBox(height: 8),
            const Text('1. Open @NCAFootballViewer_bot and send /start.\n'
                '2. Open @NCAPrivate_bot and send /whoami.\n'
                '3. Add your numeric Telegram User ID to the private '
                'Supabase secret TG_ADMIN_USER_IDS.\n'
                '4. In Private Admin Bot, send /health or /bein.'),
            const SizedBox(height: 18),
            const Text(
              'The first version supports on-demand commands. '
              'Automatic push notifications are not enabled yet.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
}
