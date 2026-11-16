import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/ignore_rules.dart';
import '../state/status.dart';

/// What the user chose in the ignore dialog.
class IgnoreChoice {
  const IgnoreChoice({required this.scope, required this.target, required this.stopTracking});

  final IgnoreScope scope;
  final IgnoreTarget target;
  final bool stopTracking;
}

/// Ask how wide the rule is and which file it goes into, showing the exact line
/// that will be written before it is written.
class IgnoreDialog extends StatefulWidget {
  const IgnoreDialog({super.key, required this.row, required this.targets});

  final StatusRow row;
  final List<IgnoreTarget> targets;

  static Future<IgnoreChoice?> show(
    BuildContext context, {
    required StatusRow row,
    required List<IgnoreTarget> targets,
  }) =>
      showDialog<IgnoreChoice>(
        context: context,
        builder: (context) => IgnoreDialog(row: row, targets: targets),
      );

  @override
  State<IgnoreDialog> createState() => _IgnoreDialogState();
}

class _IgnoreDialogState extends State<IgnoreDialog> {
  IgnoreScope scope = IgnoreScope.file;
  late IgnoreTarget target = _defaultTarget();
  late bool stopTracking = widget.row.isStaged || widget.row.section == Section.changed;

  IgnoreTarget _defaultTarget() {
    final existing = widget.targets.where((ignore) => ignore.exists).toList();
    return existing.isNotEmpty ? existing.first : widget.targets.first;
  }

  @override
  Widget build(BuildContext context) {
    final pattern = Changes.previewPattern(scope: scope, target: target, path: widget.row.path);
    return AlertDialog(
      title: Text('Ignore ${widget.row.path}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scope', style: Theme.of(context).textTheme.labelMedium),
            _scopes(),
            const SizedBox(height: 12),
            Text('Where', style: Theme.of(context).textTheme.labelMedium),
            _targets(),
            const SizedBox(height: 12),
            _tracking(),
            const SizedBox(height: 12),
            _preview(pattern),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: pattern == null
              ? null
              : () => Navigator.pop(
                    context,
                    IgnoreChoice(scope: scope, target: target, stopTracking: stopTracking),
                  ),
          child: const Text('Ignore'),
        ),
      ],
    );
  }

  Widget _scopes() => Row(
        children: [
          for (final option in IgnoreScope.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(_scopeLabel(option)),
                selected: scope == option,
                onSelected: (_) => setState(() => scope = option),
              ),
            ),
        ],
      );

  Widget _targets() => Column(
        children: [
          for (final option in widget.targets)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(_targetLabel(option)),
              subtitle: Text(option.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: option == target ? const Icon(Icons.check, size: 18) : null,
              onTap: () => setState(() => target = option),
            ),
        ],
      );

  Widget _tracking() => widget.row.section == Section.untracked
      ? const SizedBox.shrink()
      : CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: stopTracking,
          onChanged: (value) => setState(() => stopTracking = value ?? false),
          title: const Text('Also stop tracking (git rm --cached)'),
          subtitle: const Text('Ignoring does not untrack a file by itself.'),
        );

  Widget _preview(String? pattern) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          pattern == null ? 'This scope makes no rule for this file.' : 'line to write:   $pattern',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      );

  static String _scopeLabel(IgnoreScope scope) => switch (scope) {
        IgnoreScope.file => 'this file',
        IgnoreScope.extension => 'this extension',
        IgnoreScope.folder => 'this folder',
      };

  static String _targetLabel(IgnoreTarget target) => switch (target.kind) {
        IgnoreTargetKind.folderGitignore => '.gitignore in ${target.label}',
        IgnoreTargetKind.rootGitignore => 'root .gitignore',
        IgnoreTargetKind.localExclude => target.label,
        IgnoreTargetKind.globalIgnore => target.label,
      };
}
