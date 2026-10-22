import 'dart:async';

import 'package:flutter/material.dart';

/// Show a visible, retryable startup state before the authenticated Admin UI.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key, required this.initialize, required this.child});

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  static const _startupTimeout = Duration(seconds: 30);

  Future<void>? _initialization;
  bool _initializationFailed = false;
  late Future<void> _ready;

  Future<void> _initializeOnce() async {
    try {
      await widget.initialize();
    } catch (_) {
      _initializationFailed = true;
      rethrow;
    }
  }

  Future<void> _start() {
    final operation = _initialization ??= _initializeOnce();
    return operation.timeout(_startupTimeout);
  }

  void _retry() {
    // A timeout does not cancel the underlying backend/session restoration.
    // Keep waiting for that same operation instead of starting a second
    // Supabase initialization. Only a completed failure may start over.
    if (_initializationFailed) {
      _initialization = null;
      _initializationFailed = false;
    }
    setState(() {
      _ready = _start();
    });
  }

  @override
  void initState() {
    super.initState();
    _ready = _start();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return widget.child;
          }
          return Scaffold(
              body: Center(
                  child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('NCA Admin',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              if (!snapshot.hasError) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Connecting…'),
              ] else ...[
                const Text(
                    'Could not connect. Check your connection and retry.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ]),
          )));
        },
      );
}
