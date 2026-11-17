import 'dart:async';

import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/git_repo.dart';
import '../state/ignore_rules.dart';
import '../state/status.dart';
import 'app_keys.dart';
import 'theme.dart';
import 'widgets.dart';

/// What the user chose in the ignore dialog: how wide the rule is and where it
/// goes. Ignoring writes the rule and nothing else; untracking is `u`.
class IgnoreChoice {
  const IgnoreChoice({required this.scope, required this.target});

  final IgnoreScope scope;
  final IgnoreTarget target;
}

/// Ask how wide the rule is and which file it goes into, showing the exact lines
/// that will be written before they are written.
///
/// Keys ([ignoreDialogBindings]): `1`/`2`/`3` (or `f`/`x`/`d`) pick the scope,
/// `j`/`k` or the arrows move through the targets, `Enter` writes, `Esc`
/// cancels.
class IgnoreDialog extends StatefulWidget {
  const IgnoreDialog({super.key, required this.changes, required this.row, required this.targets});

  final Changes changes;
  final StatusRow row;
  final List<IgnoreTarget> targets;

  static Future<IgnoreChoice?> show(
    BuildContext context, {
    required Changes changes,
    required StatusRow row,
    required List<IgnoreTarget> targets,
  }) =>
      showDialog<IgnoreChoice>(
        context: context,
        builder: (context) => IgnoreDialog(changes: changes, row: row, targets: targets),
      );

  static String scopeLabel(IgnoreScope scope) => switch (scope) {
        IgnoreScope.file => 'this file',
        IgnoreScope.extension => 'this extension',
        IgnoreScope.folder => 'this folder',
      };

  static String targetLabel(IgnoreTarget target) => switch (target.kind) {
        IgnoreTargetKind.folderGitignore => '.gitignore in ${target.label}',
        IgnoreTargetKind.rootGitignore => 'root .gitignore',
        IgnoreTargetKind.localExclude => target.label,
        IgnoreTargetKind.globalIgnore => target.label,
      };

  @override
  State<IgnoreDialog> createState() => IgnoreDialogState();
}

class IgnoreDialogState extends State<IgnoreDialog> {
  final FocusNode keys = FocusNode(debugLabel: 'ignore dialog');
  IgnoreScope scope = IgnoreScope.file;
  late IgnoreTarget target = _defaultTarget();

  /// The highlighted rows git already ignores, once `check-ignore` has answered.
  Map<String, IgnoreMatch> ignored = const {};

  IgnoreTarget _defaultTarget() {
    final existing = widget.targets.where((ignore) => ignore.exists).toList();
    return existing.isNotEmpty ? existing.first : widget.targets.first;
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadIgnored());
    WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? keys.requestFocus() : null);
  }

  @override
  void dispose() {
    keys.dispose();
    super.dispose();
  }

  Future<void> loadIgnored() async {
    final found = await widget.changes.alreadyIgnored();
    if (mounted && found.isNotEmpty) setState(() => ignored = found);
  }

  IgnorePreview get preview => widget.changes.ignorePreview(scope: scope, target: target);

  void pickScope(IgnoreScope next) => setState(() => scope = next);

  void pickTarget(IgnoreTarget next) => setState(() => target = next);

  /// `j`/`k`: the next or previous target, stopping at the ends.
  void stepTarget(int delta) {
    final at = widget.targets.indexOf(target);
    pickTarget(widget.targets[(at + delta).clamp(0, widget.targets.length - 1)]);
  }

  /// Enter and the Ignore button: close with the choice, unless nothing would be
  /// written.
  void confirm() {
    if (preview.blocked) return;
    Navigator.pop(context, IgnoreChoice(scope: scope, target: target));
  }

  void cancel() => Navigator.pop(context);

  late final Map<Type, Action<Intent>> _actions = {
    ScopeIntent: CallbackAction<ScopeIntent>(onInvoke: (intent) => pickScope(IgnoreScope.values[intent.index])),
    MoveIntent: CallbackAction<MoveIntent>(onInvoke: (intent) => stepTarget(intent.delta.sign)),
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => confirm()),
    DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => cancel()),
  };

  @override
  Widget build(BuildContext context) {
    final current = preview;
    final count = widget.changes.actionRows.length;
    return KeyScope(
      bindings: const [...motionBindings, ...ignoreDialogBindings],
      actions: _actions,
      focusNode: keys,
      child: AlertDialog(
        title: Text(count > 1 ? 'Ignore $count files' : 'Ignore ${widget.row.path}'),
        content: SizedBox(
          width: 520,
          child: _DialogBody(
            scope: scope,
            targets: widget.targets,
            target: target,
            preview: current,
            ignored: ignored,
            place: widget.changes.matchPlace,
            onScope: pickScope,
            onTarget: pickTarget,
          ),
        ),
        actions: [
          SmallButton(label: 'Cancel', tooltip: 'Close without writing (Esc)', onPressed: cancel),
          SmallButton(
            label: 'Ignore',
            tooltip: 'Write ${current.summary} (Enter)',
            onPressed: current.blocked ? null : confirm,
            filled: true,
          ),
        ],
      ),
    );
  }
}

/// Scope, targets and preview, top to bottom.
class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.scope,
    required this.targets,
    required this.target,
    required this.preview,
    required this.ignored,
    required this.place,
    required this.onScope,
    required this.onTarget,
  });

  final IgnoreScope scope;
  final List<IgnoreTarget> targets;
  final IgnoreTarget target;
  final IgnorePreview preview;
  final Map<String, IgnoreMatch> ignored;
  final String Function(IgnoreMatch) place;
  final ValueChanged<IgnoreScope> onScope;
  final ValueChanged<IgnoreTarget> onTarget;

  @override
  Widget build(BuildContext context) {
    final labels = Theme.of(context).textTheme.labelMedium;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scope  (1 2 3, or f x d)', style: labels),
        _ScopeChips(current: scope, onPick: onScope),
        const SizedBox(height: T.gap12),
        Text('Where  (j / k)', style: labels),
        for (final option in targets)
          _TargetTile(target: option, chosen: option == target, onPick: onTarget),
        const SizedBox(height: T.gap12),
        _Preview(preview: preview, ignored: ignored, place: place),
      ],
    );
  }
}

class _ScopeChips extends StatelessWidget {
  const _ScopeChips({required this.current, required this.onPick});

  final IgnoreScope current;
  final ValueChanged<IgnoreScope> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (index, option) in IgnoreScope.values.indexed)
          Padding(
            padding: const EdgeInsets.only(right: T.gap6),
            child: Clickable(
              tooltip: 'Scope: ${IgnoreDialog.scopeLabel(option)} (${index + 1})',
              child: ChoiceChip(
                label: Text(IgnoreDialog.scopeLabel(option)),
                selected: current == option,
                onSelected: (_) => onPick(option),
              ),
            ),
          ),
      ],
    );
  }
}

/// One file a rule can go into: its name, its path, and a check when chosen.
class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.target, required this.chosen, required this.onPick});

  final IgnoreTarget target;
  final bool chosen;
  final ValueChanged<IgnoreTarget> onPick;

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      key: ValueKey('ignore-target-${target.path}'),
      tooltip: 'Write the rule to ${target.path}',
      onTap: () => onPick(target),
      decoration: chosen ? const BoxDecoration(color: T.chosen) : null,
      padding: const EdgeInsets.symmetric(vertical: T.gap4, horizontal: T.gap6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(IgnoreDialog.targetLabel(target), style: T.body),
                Text(target.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              ],
            ),
          ),
          if (chosen) const Icon(Icons.check, size: T.icon),
        ],
      ),
    );
  }
}

/// The lines about to be written, each once, and what would not be.
class _Preview extends StatelessWidget {
  const _Preview({required this.preview, required this.ignored, required this.place});

  final IgnorePreview preview;
  final Map<String, IgnoreMatch> ignored;
  final String Function(IgnoreMatch) place;

  List<String> get _lines => [
        ...preview.rules.take(8),
        if (preview.rules.length > 8) '… ${preview.rules.length - 8} more',
        for (final name in preview.missing) '$name: no rule for this scope',
        for (final MapEntry(:key, :value) in ignored.entries)
          '$key: already ignored by `${value.pattern}` in ${place(value)}',
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(T.gap8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(preview.summary, style: theme.textTheme.labelSmall),
          const SizedBox(height: T.gap4),
          for (final line in _lines) Text(line, style: T.code),
        ],
      ),
    );
  }
}
