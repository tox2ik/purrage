import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The filter field at the top of the file list, the way Ops does it: `/` puts
/// the keyboard here, Esc clears then leaves, Enter, Tab and Down go back to the
/// list.
class FilterField extends StatelessWidget {
  const FilterField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Focus(
        onKeyEvent: _onKey,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 15),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIcon: _ClearButton(controller: controller, onCleared: onChanged),
            suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            hintText: 'Filter (/)',
          ),
          onChanged: onChanged,
          onSubmitted: (_) => focusNode.unfocus(),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (controller.text.isEmpty) {
          focusNode.unfocus();
        } else {
          controller.clear();
          onChanged('');
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.tab:
        focusNode.unfocus();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.controller, required this.onCleared});

  final TextEditingController controller;
  final ValueChanged<String> onCleared;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? const SizedBox.shrink()
            : Tooltip(
                message: 'Clear the filter',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 15),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      controller.clear();
                      onCleared('');
                    },
                  ),
                ),
              ),
      );
}
