import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/status.dart';
import 'commit_bar.dart';
import 'file_list.dart';
import 'preview.dart';

/// The Changes mode: the file list on the left, the preview on the right, the
/// commit bar across the bottom. The split between them is dragged with the
/// mouse and starts wide enough for ordinary paths.
class ChangesView extends StatefulWidget {
  const ChangesView({
    super.key,
    required this.changes,
    required this.commitController,
    required this.commitFocus,
    required this.onIgnore,
    required this.filterController,
    required this.filterFocus,
  });

  final Changes changes;
  final TextEditingController commitController;
  final FocusNode commitFocus;
  final VoidCallback onIgnore;
  final TextEditingController filterController;
  final FocusNode filterFocus;

  @override
  State<ChangesView> createState() => _ChangesViewState();
}

class _ChangesViewState extends State<ChangesView> {
  /// Wide enough for most paths; outliers are cut with an ellipsis rather than
  /// widening the pane.
  static const double startingWidth = 460;
  static const double minWidth = 260;
  static const double maxWidth = 820;

  double width = startingWidth;

  @override
  Widget build(BuildContext context) {
    final changes = widget.changes;
    return ListenableBuilder(
      listenable: changes,
      builder: (context, _) => Column(
        children: [
          if (changes.error != null) _ErrorBanner(message: changes.error!),
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: width,
                  child: FileList(
                    changes: changes,
                    onIgnore: widget.onIgnore,
                    filterController: widget.filterController,
                    filterFocus: widget.filterFocus,
                  ),
                ),
                SplitHandle(
                  onDrag: (delta) => setState(() {
                    width = (width + delta).clamp(minWidth, maxWidth);
                  }),
                ),
                Expanded(
                  child: PreviewPane(
                    preview: changes.preview,
                    path: changes.previewPath,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          CommitBar(
            changes: changes,
            controller: widget.commitController,
            focusNode: widget.commitFocus,
          ),
        ],
      ),
    );
  }
}

/// The divider between the list and the preview: a grab bar that resizes the
/// list while the mouse drags it.
class SplitHandle extends StatelessWidget {
  const SplitHandle({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Drag to resize the file list',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          child: const SizedBox(
            width: 7,
            child: Center(child: SizedBox(width: 1, child: ColoredBox(color: Color(0x33FFFFFF)))),
          ),
        ),
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
