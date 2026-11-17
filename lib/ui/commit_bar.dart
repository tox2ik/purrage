import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/changes.dart';
import 'theme.dart';
import 'widgets.dart';

/// The bottom bar: one summary line and a Commit button that is only enabled
/// when something is staged.
///
/// The commit itself runs in the shell, so its failure reaches the notice and the
/// console like every other action. Enter and Ctrl+Enter in the field commit.
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

  void submit() => unawaited(onCommit(controller.text));

  /// Listens to the status only (busy, staged count): a cursor move does not
  /// rebuild the field or the button.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: changes.status,
        builder: (context, _) => _bar(),
      );

  Widget _bar() {
    final blocked = changes.commitBlockedReason;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: _MessageField(
              controller: controller,
              focusNode: focusNode,
              blockedReason: blocked,
              onSubmit: submit,
            ),
          ),
          const SizedBox(width: T.gap8),
          _CommitButton(staged: changes.stagedCount, blockedReason: blocked, onPressed: submit),
        ],
      ),
    );
  }
}

/// The summary field: read-only with the reason as its hint while nothing can
/// be committed, and a quiet `73/72` once the summary is longer than git likes.
class _MessageField extends StatelessWidget {
  const _MessageField({
    required this.controller,
    required this.focusNode,
    required this.blockedReason,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? blockedReason;
  final VoidCallback onSubmit;

  static const hint = 'Summary line, e.g. state: parse porcelain status';

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): onSubmit},
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          focusNode: focusNode,
          // Read-only, not disabled: disabling a focused field removes its
          // accessibility node on Windows ("Failed to update ui::AXTree"),
          // and the commit button already gates the action.
          readOnly: blockedReason != null,
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            labelText: 'Commit message',
            hintText: blockedReason ?? hint,
            suffixText: _counter(value.text),
            suffixStyle: T.tiny,
          ),
          onSubmitted: (_) => onSubmit(),
        ),
      ),
    );
  }

  static String? _counter(String text) {
    final length = text.trim().length;
    return length > Changes.summaryLimit ? '$length/${Changes.summaryLimit}' : null;
  }
}

/// `Commit` or `Commit 3`, with a tooltip that says why it is disabled.
class _CommitButton extends StatelessWidget {
  const _CommitButton({required this.staged, required this.blockedReason, required this.onPressed});

  final int staged;
  final String? blockedReason;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final files = staged == 1 ? '1 staged file' : '$staged staged files';
    return Clickable(
      tooltip: blockedReason ?? 'Commit $files (Enter or Ctrl+Enter in the message; c goes there)',
      enabled: blockedReason == null,
      child: FilledButton(
        onPressed: blockedReason == null ? onPressed : null,
        child: Text(staged > 0 ? 'Commit $staged' : 'Commit'),
      ),
    );
  }
}
