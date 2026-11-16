import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/status.dart';
import 'commit_bar.dart';
import 'file_list.dart';
import 'preview.dart';

/// The Changes mode: the file list on the left, the preview on the right, the
/// commit bar across the bottom.
class ChangesView extends StatelessWidget {
  const ChangesView({
    super.key,
    required this.changes,
    required this.commitController,
    required this.commitFocus,
  });

  final Changes changes;
  final TextEditingController commitController;
  final FocusNode commitFocus;

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
                SizedBox(
                  width: 340,
                  child: FileList(changes: changes),
                ),
                const VerticalDivider(width: 1),
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
            controller: commitController,
            focusNode: commitFocus,
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
