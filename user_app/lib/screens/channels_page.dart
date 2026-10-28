import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../native_player.dart';
import '../network_endpoints.dart';
import '../widgets/premium_bottom_nav.dart';
import 'home_page.dart';
import 'source_browser_page.dart';

class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key});
  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  final search = TextEditingController();
  late Future<List<Map<String, dynamic>>> catalog = load();
  String? workingBase;
  bool opening = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool matchesSearch(Map<String, dynamic> row) {
    String normalized(String value) => value
        .toLowerCase()
        .replaceAllMapped(RegExp(r'([a-z])([0-9])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[\s_-]+'), ' ')
        .trim();
    final text = normalized('${row['name'] ?? ''} ${row['category'] ?? ''}');
    return normalized(
      search.text,
    ).split(' ').where((s) => s.isNotEmpty).every(text.contains);
  }

  Future<Map<String, dynamic>> request(String path) async {
    final bases = publicApiBases();
    if (workingBase != null && bases.remove(workingBase))
      bases.insert(0, workingBase!);
    final result = Completer<Map<String, dynamic>>();
    Object? lastError;
    var next = 0;
    var pending = 0;

    void startNext() {
      if (result.isCompleted || next >= bases.length) return;
      final base = bases[next++];
      pending++;
      () async {
        try {
          final response = await http
              .get(
                Uri.parse('$base$path'),
                headers: const {'Accept': 'application/json'},
              )
              .timeout(const Duration(seconds: 7));
          if (response.statusCode != 200) {
            throw StateError('HTTP ${response.statusCode}');
          }
          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['ok'] != true) {
            throw const FormatException('Invalid channel response');
          }
          if (!result.isCompleted) {
            workingBase = base;
            result.complete(Map<String, dynamic>.from(decoded));
          }
        } catch (error) {
          lastError = error;
        } finally {
          pending--;
          if (!result.isCompleted) {
            // A failed route should not delay the next candidate.
            if (next < bases.length) startNext();
            if (next == bases.length && pending == 0) {
              result.completeError(
                StateError('Channel service unavailable: $lastError'),
              );
            }
          }
        }
      }();
    }

    startNext();
    final hedge = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (result.isCompleted || next >= bases.length) {
        timer.cancel();
      } else {
        startNext();
      }
    });
    try {
      return await result.future;
    } finally {
      hedge.cancel();
    }
  }

  Future<List<Map<String, dynamic>>> load() async {
    final data = await request('/channels');
    if (data['channels'] is! List)
      throw const FormatException('Invalid channel catalog');
    return (data['channels'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> refresh() async {
    setState(() => catalog = load());
    try {
      await catalog;
    } catch (_) {}
  }

  Future<void> watch(Map<String, dynamic> channel) async {
    if (opening) return;
    final id = channel['id']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return;
    setState(() => opening = true);
    try {
      final data = await request('/channels/$id/streams');
      if (data['streams'] is! List)
        throw const FormatException('Invalid channel lines');
      final lines = (data['streams'] as List)
          .whereType<Map>()
          .map((raw) {
            final row = Map<String, dynamic>.from(raw);
            final url = row['stream_url']?.toString() ?? '';
            final uri = Uri.tryParse(url);
            if (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                row['protected_proxy'] != true)
              return null;
            return <String, dynamic>{
              'id': row['id']?.toString(),
              'label': row['label']?.toString() ?? 'Server',
              'url': url,
              'streamType': row['stream_type']?.toString() ?? 'auto',
              'keyId': row['key_id']?.toString() ?? '',
              'keyData': row['key_data']?.toString() ?? '',
              'portraitStart': true,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active stream line for this channel.'),
          ),
        );
        return;
      }
      NativePlayer.prewarm(sources: lines);
      await NativePlayer.open(
        context: context,
        sources: lines,
        selectedIndex: 0,
        title: channel['name']?.toString() ?? 'Channel',
        matchId: id,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open channel: $error')),
        );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  void navigate(int index) {
    if (index == 5) {
      unawaited(refresh());
      return;
    }
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
      return;
    }
    final source = switch (index) {
      2 => 'yyzb',
      3 => 'fawa',
      4 => 'cola',
      6 => 'xoilac',
      7 => 'camel',
      _ => 'soco',
    };
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SourceBrowserPage(source: source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Channels'),
      actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh)),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search channels',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: catalog,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError)
          return Center(
            child: Text('Channel catalog unavailable: ${snapshot.error}'),
          );
        final groups = <String, List<Map<String, dynamic>>>{};
        for (final row in snapshot.data!.where(matchesSearch)) {
          final category = row['category']?.toString().trim() ?? 'Other';
          groups
              .putIfAbsent(category.isEmpty ? 'Other' : category, () => [])
              .add(row);
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (groups.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      snapshot.data!.isEmpty
                          ? 'No published channels yet.'
                          : 'No matching channels.',
                    ),
                  ),
                ),
              for (final group in groups.entries) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  sliver: SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${group.key} (${group.value.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 150,
                        ),
                    itemCount: group.value.length,
                    itemBuilder: (context, index) {
                      final channel = group.value[index];
                      final image = channel['image_url']?.toString() ?? '';
                      final title = channel['name']?.toString() ?? 'Channel';
                      return SizedBox(
                        width: 160,
                        child: InkWell(
                          onTap: () => watch(channel),
                          child: Column(
                            children: [
                              Expanded(
                                child: Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: Center(
                                    child: image.startsWith('https://')
                                        ? Image.network(
                                            image,
                                            fit: BoxFit.contain,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.tv),
                                          )
                                        : const Icon(Icons.tv, size: 38),
                                  ),
                                ),
                              ),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
    bottomNavigationBar: PremiumBottomNav(
      selectedIndex: 5,
      onSelected: navigate,
    ),
  );
}
