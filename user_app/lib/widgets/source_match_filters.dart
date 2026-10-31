import 'package:flutter/material.dart';

class SourceMatchFilters extends StatelessWidget {
  const SourceMatchFilters({
    super.key,
    required this.controller,
    required this.todayOnly,
    required this.leagues,
    required this.league,
    required this.visibleCount,
    this.onRefresh,
    required this.onQueryChanged,
    required this.onTodayChanged,
    required this.onLeagueChanged,
  });

  final TextEditingController controller;
  final bool todayOnly;
  final List<String> leagues;
  final String? league;
  final int visibleCount;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onTodayChanged;
  final ValueChanged<String?> onLeagueChanged;

  Future<void> _pickLeague(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LeaguePicker(leagues: leagues, selected: league),
    );
    if (selected != null) onLeagueChanged(selected.isEmpty ? null : selected);
  }

  Widget _filterChoices(BuildContext context) {
    final today = ChoiceChip(
      label: const Text('Today', style: TextStyle(fontSize: 12)),
      selected: todayOnly,
      onSelected: (_) => onTodayChanged(true),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final allDates = ChoiceChip(
      label: const Text('All dates', style: TextStyle(fontSize: 12)),
      selected: !todayOnly,
      onSelected: (_) => onTodayChanged(false),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final leagueButton = OutlinedButton(
      onPressed: () => _pickLeague(context),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_rounded, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              league ?? 'All leagues',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Icon(Icons.expand_more_rounded, size: 16),
        ],
      ),
    );
    // Give enlarged accessibility text its own rows instead of squeezing the
    // date choices and league picker into a single phone-width row.
    if (MediaQuery.textScalerOf(context).scale(14) > 17) {
      return Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          today,
          allDates,
          SizedBox(width: double.infinity, child: leagueButton),
        ],
      );
    }
    return Row(
      children: [
        today,
        const SizedBox(width: 5),
        allDates,
        const SizedBox(width: 6),
        Expanded(child: leagueButton),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 43, child: TextField(
            key: const ValueKey('source-match-search'),
            controller: controller,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search teams or leagues',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              prefixIconConstraints: const BoxConstraints(minWidth: 37, minHeight: 35),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          )),
          const SizedBox(height: 4),
          _filterChoices(context),
          Row(
            children: [
              Expanded(child: Text(
                '$visibleCount ${visibleCount == 1 ? 'match' : 'matches'}',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
              )),
              IconButton(
                tooltip: 'Refresh matches',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minHeight: 36, minWidth: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaguePicker extends StatefulWidget {
  const _LeaguePicker({required this.leagues, required this.selected});
  final List<String> leagues;
  final String? selected;
  @override
  State<_LeaguePicker> createState() => _LeaguePickerState();
}

class _LeaguePickerState extends State<_LeaguePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final leagues = widget.leagues
        .where(
          (name) => name.toLowerCase().contains(_query.toLowerCase().trim()),
        )
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search leagues',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: leagues.length + 1,
                  itemBuilder: (context, index) {
                    final name = index == 0 ? '' : leagues[index - 1];
                    final selected = name.isEmpty
                        ? widget.selected == null
                        : widget.selected == name;
                    return ListTile(
                      title: Text(name.isEmpty ? 'All leagues' : name),
                      trailing: selected
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(context, name),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
