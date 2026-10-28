import 'package:flutter/material.dart';

class ChannelSearchField extends StatelessWidget {
  const ChannelSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search channels',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
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
      );
}
