import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

/// The filter field at the top of a list, the way Ops does it: `/` puts the
/// keyboard here, Esc clears then leaves, Enter and Down go back to the list;
/// Tab goes on to the next pane like everywhere else.
class FilterField extends StatelessWidget {
  const FilterField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onDone,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// Where the keyboard goes when the field is left (the list); without it
  /// the field just lets go.
  final VoidCallback? onDone;

  void _leave() => (onDone ?? focusNode.unfocus)();

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
            prefixIcon: const Icon(Icons.search, size: T.iconSmall),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            suffixIcon: _ClearButton(controller: controller, onCleared: onChanged),
            suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            hintText: 'Filter (/)',
          ),
          onChanged: onChanged,
          onSubmitted: (_) => _leave(),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        if (controller.text.isEmpty) {
          _leave();
        } else {
          controller.clear();
          onChanged('');
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.enter:
        _leave();
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

  /// Empty the field and report the empty text, as typing would.
  void _clear() {
    controller.clear();
    onCleared('');
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? const SizedBox.shrink()
            : IconAction(
                icon: Icons.close,
                size: T.iconSmall,
                tooltip: 'Clear the filter (Esc)',
                onPressed: _clear,
              ),
      );
}
