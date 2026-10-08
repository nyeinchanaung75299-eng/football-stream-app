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
  late Future<void> _ready;

  Future<void> _start() =>
      Future<void>.sync(widget.initialize).timeout(const Duration(seconds: 12));

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
                FilledButton(
                    onPressed: () => setState(() {
                          _ready = _start();
                        }),
                    child: const Text('Retry')),
              ],
            ]),
          )));
        },
      );
}
