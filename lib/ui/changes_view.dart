import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/ignore_files.dart';
import '../state/status.dart';
import 'commit_bar.dart';
import 'file_list.dart';
import 'ignore_pane.dart';

/// The Changes mode: the file list, the commit bar across the bottom.
class ChangesView extends StatelessWidget {
  const ChangesView({
    super.key,
    required this.changes,
    required this.commitController,
    required this.commitFocus,
    required this.onIgnore,
    required this.onQuickIgnore,
    required this.onTrack,
    required this.onUntrack,
    required this.onOpen,
    required this.onReload,
    required this.filterController,
    required this.filterFocus,
    required this.ignoreState,
    required this.onOpenIgnore,
    required this.onNewIgnore,
    required this.onCommit,
    required this.listFocus,
    this.railFocus,
    this.linesFocus,
  });

  /// The Tab stops besides the two text fields: the list, the ignore rail and
  /// the ignore lines.
  final FocusNode listFocus;
  final FocusNode? railFocus;
  final FocusNode? linesFocus;

  final Changes changes;
  final TextEditingController commitController;
  final FocusNode commitFocus;
  final VoidCallback onIgnore;
  final VoidCallback onQuickIgnore;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onOpen;
  final VoidCallback onReload;
  final TextEditingController filterController;
  final FocusNode filterFocus;
  final IgnorePaneState ignoreState;
  final VoidCallback onOpenIgnore;
  final VoidCallback onNewIgnore;
  final Future<void> Function(String summary) onCommit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) => Column(
        children: [
          if (changes.error != null) _ErrorBanner(message: changes.error!),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: FileList(
                    changes: changes,
                    onIgnore: onIgnore,                    onQuickIgnore: onQuickIgnore,
                    onTrack: onTrack,
                    onUntrack: onUntrack,
                    onOpen: onOpen,
                    onReload: onReload,
                    filterController: filterController,
                    filterFocus: filterFocus,
                    listFocus: listFocus,
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 360,
                  child: IgnorePane(
                    state: ignoreState,
                    onOpenInEditor: onOpenIgnore,
                    onNewHere: onNewIgnore,
                    railFocus: railFocus,
                    linesFocus: linesFocus,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          CommitBar(
            changes: changes,
            controller: commitController,
            focusNode: commitFocus,
            onCommit: onCommit,
          ),
        ],
      ),
    );
  }
}
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(8),
      child: SelectableText(
        message,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

/// Section heading inside the list.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.section, required this.count});

  final Section section;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Text('${_label(section)} ($count)', style: style),
    );
  }

  static String _label(Section section) => switch (section) {
        Section.conflicts => 'Conflicts',
        Section.staged => 'Staged',
        Section.changed => 'Changed',
        Section.untracked => 'Untracked',
      };
}
