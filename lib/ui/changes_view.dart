import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/ignore_files.dart';
import '../state/pane_layout.dart';
import '../state/status.dart';
import 'commit_bar.dart';
import 'file_list.dart';
import 'ignore_pane.dart';
import 'resizable_pane.dart';
import 'widgets.dart';

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
    this.paneLayout,
    this.onOpenIgnoreFile,
  });

  /// The ignore pane's width and visibility (resizable, hidden on a narrow
  /// window); null gives the fixed default width.
  final PaneLayout? paneLayout;

  /// Open an ignore file outside the pane's rail (exclude, global).
  final ValueChanged<String>? onOpenIgnoreFile;

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

  /// Built once per Changes, not per notify: each part listens to the slice of
  /// [Changes] it shows (the list to the rows and the cursor, the banner and the
  /// commit bar to the status), so a cursor move redraws only the list.
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ErrorBanner(changes: changes),
        Expanded(
          child: Row(
            children: [
              Expanded(child: PaneMark(nodes: [listFocus], child: _list())),
              _SidePane(
                layout: paneLayout,
                child: PaneMark(nodes: [railFocus, linesFocus], child: _ignorePane()),
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
    );
  }

  Widget _list() => FileList(
        changes: changes,
        onIgnore: onIgnore,
        onQuickIgnore: onQuickIgnore,
        onTrack: onTrack,
        onUntrack: onUntrack,
        onOpen: onOpen,
        onReload: onReload,
        filterController: filterController,
        filterFocus: filterFocus,
        listFocus: listFocus,
      );

  Widget _ignorePane() => IgnorePane(
        state: ignoreState,
        onOpenInEditor: onOpenIgnore,
        onNewHere: onNewIgnore,
        railFocus: railFocus,
        linesFocus: linesFocus,
        onOpenFile: onOpenIgnoreFile,
      );
}

/// The ignore pane on the right: resizable by its edge, hidden on a narrow
/// window (or by `p`), so the file list never loses its room first. Without a
/// [layout] it is the default width, with a plain divider.
class _SidePane extends StatelessWidget {
  const _SidePane({required this.layout, required this.child});

  final PaneLayout? layout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = this.layout;
    if (layout == null) {
      return Row(children: [
        const VerticalDivider(width: 1),
        SizedBox(width: PaneLayout.defaultWidth, child: child),
      ]);
    }
    final room = MediaQuery.sizeOf(context).width;
    return ListenableBuilder(
      listenable: layout,
      builder: (context, _) => layout.shownIn(room)
          ? ResizablePane(layout: layout, room: room, child: child)
          : const SizedBox.shrink(),
    );
  }
}

/// git's error from the last load or refresh, across the top; nothing when
/// there is none. Listens to the status only.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.changes});

  final Changes changes;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: changes.status,
        builder: (context, _) {
          final message = changes.error;
          return message == null ? const SizedBox.shrink() : _ErrorText(message: message);
        },
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

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
    // The list gives it exactly T.sectionHeaderHeight; the label sits at the
    // bottom, close to its rows.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text('${_label(section)} ($count)', style: style, maxLines: 1),
      ),
    );
  }

  static String _label(Section section) => switch (section) {
        Section.conflicts => 'Conflicts',
        Section.staged => 'Staged',
        Section.changed => 'Changed',
        Section.untracked => 'Untracked',
      };
}
