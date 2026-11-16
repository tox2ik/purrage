import 'package:flutter/material.dart';

import '../state/changes.dart';

/// The bottom bar: one summary line and a Commit button that is only enabled
/// when something is staged.
class CommitBar extends StatelessWidget {
  const CommitBar({
    super.key,
    required this.changes,
    required this.controller,
    required this.focusNode,
  });

  final Changes changes;
  final TextEditingController controller;
  final FocusNode focusNode;

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
              enabled: changes.canCommit,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Commit message',
                hintText: 'Summary line, e.g. state: parse porcelain status',
              ),
              onSubmitted: (value) => _commit(context),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: changes.canCommit ? () => _commit(context) : null,
            child: Text('Commit ${changes.stagedCount}'),
          ),
        ],
      ),
    );
  }

  Future<void> _commit(BuildContext context) async {
    final ok = await changes.commit(controller.text);
    if (ok) {
      controller.clear();
      return;
    }
    if (changes.error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changes.error!)),
      );
    }
  }
}
