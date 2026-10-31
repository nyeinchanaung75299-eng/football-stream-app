import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/channel_group_order_service.dart';

/// Admin-managed persistent group order. No channel records are modified.
class ChannelGroupOrderPage extends StatefulWidget {
  const ChannelGroupOrderPage({super.key});

  @override
  State<ChannelGroupOrderPage> createState() => _ChannelGroupOrderPageState();
}

class _ChannelGroupOrderPageState extends State<ChannelGroupOrderPage> {
  List<String>? groups;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  ChannelGroupOrderService get service =>
      ChannelGroupOrderService(Supabase.instance.client);

  Future<void> _load() async {
    try {
      final rows = await service.categoriesInOrder();
      if (mounted) setState(() { groups = rows; error = null; });
    } catch (_) {
      if (mounted) setState(() { error = 'Could not load channel group order.'; });
    }
  }

  void _move(int from, int to) {
    final items = groups;
    if (items == null || to < 0 || to >= items.length || saving) return;
    setState(() {
      final value = items.removeAt(from);
      items.insert(to, value);
    });
  }

  Future<void> _save() async {
    if (saving || groups == null) return;
    setState(() => saving = true);
    try {
      await service.save(groups!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Channel group order saved.')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() { error = 'Saving failed. Please retry.'; });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reorder Channel Groups')),
    body: groups == null
        ? Center(child: error == null
            ? const CircularProgressIndicator()
            : FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('RETRY'),
              ))
        : Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Use the arrows to arrange channel groups. Save to apply the order to Admin channel lists and TV guide.'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: groups!.length,
                itemBuilder: (context, index) => ListTile(
                  key: ValueKey(groups![index]),
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(groups![index]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: index == 0 || saving ? null : () => _move(index, index - 1),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: index == groups!.length - 1 || saving ? null : () => _move(index, index + 1),
                      icon: const Icon(Icons.arrow_downward_rounded),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'SAVING…' : 'SAVE GROUP ORDER'),
                ),
              ),
            ),
          ]),
  );
}
