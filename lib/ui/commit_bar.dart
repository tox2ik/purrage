import 'package:flutter/material.dart';

import '../state/changes.dart';

/// The bottom bar: one summary line and a Commit button that is only enabled
/// when something is staged.
///
/// The commit itself runs in the shell, so its failure reaches the notice and the
/// console like every other action.
class CommitBar extends StatelessWidget {
  const CommitBar({
    super.key,
    required this.changes,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
  });

  final Changes changes;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(String summary) onCommit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              // Read-only, not disabled: disabling a focused field removes its
              // accessibility node on Windows ("Failed to update ui::AXTree"),
              // and the commit button already gates the action.
              readOnly: !changes.canCommit,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Commit message',
                hintText: 'Summary line, e.g. state: parse porcelain status',
              ),
              onSubmitted: onCommit,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: changes.canCommit ? () => onCommit(controller.text) : null,
            child: Text('Commit ${changes.stagedCount}'),
          ),
        ],
      ),
    );
  }
}
