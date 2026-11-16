import 'package:flutter/material.dart';

import '../state/changes.dart';
import '../state/status.dart';
import 'changes_view.dart';
import 'filter_field.dart';

/// The list itself: one row per staged/changed/untracked path, grouped by
/// section, with the focused row kept in view.
class FileList extends StatefulWidget {
  const FileList({
    super.key,
    required this.changes,
    required this.onIgnore,
    required this.filterController,
    required this.filterFocus,
  });

  final Changes changes;
  final VoidCallback onIgnore;
  final TextEditingController filterController;
  final FocusNode filterFocus;

  @override
  State<FileList> createState() => _FileListState();
}

class _FileListState extends State<FileList> {
  final ScrollController scroll = ScrollController();
  final Map<int, GlobalKey> keys = {};

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_reveal);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_reveal);
    scroll.dispose();
    super.dispose();
  }

  /// Keep the focused row on screen after a move.
  void _reveal() {
    final index = widget.changes.index;
    final key = keys[index];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 120));
  }

  @override
  Widget build(BuildContext context) {
    final changes = widget.changes;
    final filter = FilterField(
      controller: widget.filterController,
      focusNode: widget.filterFocus,
      onChanged: changes.setFilter,
    );
    if (changes.rows.isEmpty) {
      return Column(
        children: [
          filter,
          const Expanded(
            child: Center(child: Text('Nothing to commit, working tree clean.')),
          ),
        ],
      );
    }
    if (changes.visible.isEmpty) {
      return Column(
        children: [
          filter,
          Expanded(child: Center(child: Text('No path matches "${changes.filter}".'))),
        ],
      );
    }
    final children = <Widget>[];
    var flat = 0;
    for (final section in Section.values) {
      final rows = changes.section(section);
      if (rows.isEmpty) continue;
      children.add(SectionHeader(section: section, count: rows.length));
      for (final row in rows) {
        final index = flat++;
        keys[index] = GlobalKey();
        children.add(RowTile(
          key: keys[index],
          row: row,
          focused: index == changes.index,
          onTap: () => changes.select(index),
          onTrack: () => changes.trackSelected(),
          onUntrack: () => changes.untrackSelected(),
          onIgnore: () {
            changes.select(index);
            widget.onIgnore();
          },
        ));
      }
    }
    return Column(
      children: [
        filter,
        Expanded(
          child: ListView(controller: scroll, children: children),
        ),
      ],
    );
  }
}

/// One file row: status letter, name, folder, and the actions at the end.
class RowTile extends StatelessWidget {
  const RowTile({
    super.key,
    required this.row,
    required this.focused,
    required this.onTap,
    required this.onTrack,
    required this.onUntrack,
    required this.onIgnore,
  });

  final StatusRow row;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Tooltip(
      message: _tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          onSecondaryTap: onIgnore,
          child: Container(
            color: focused ? scheme.secondaryContainer : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                _Badge(text: _badge, color: scheme.outline),
                const SizedBox(width: 8),
                Expanded(child: _name(style, scheme)),
                if (row.isStaged)
                  _Action(icon: Icons.remove_circle_outline, tooltip: 'Untrack', onTap: onUntrack)
                else if (!row.isConflict)
                  _Action(icon: Icons.add_circle_outline, tooltip: 'Track', onTap: onTrack),
                _Action(icon: Icons.block, tooltip: 'Ignore', onTap: onIgnore),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Folder first, then the name, each in a fixed share of the row, so the file
  /// names line up under each other whatever the folder depths are.
  Widget _name(TextStyle? style, ColorScheme scheme) => Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              row.folder.isEmpty ? '' : '${row.folder}/',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: style?.copyWith(color: scheme.outline, fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: style,
            ),
          ),
        ],
      );

  String get _badge => switch (row.kind) {
        RowKind.added => 'A',
        RowKind.modified => 'M',
        RowKind.deleted => 'D',
        RowKind.renamed => 'R',
        RowKind.copied => 'C',
        RowKind.typeChanged => 'T',
        RowKind.untracked => 'U',
        RowKind.conflicted => '!',
      };

  String get _tooltip => switch (row.section) {
        Section.staged => 'Staged: ${row.path}',
        Section.changed => 'Changed: ${row.path}',
        Section.untracked => 'Untracked: ${row.path}',
        Section.conflicts => 'Conflict: ${row.path}',
      };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        child: Text(text, style: TextStyle(fontFamily: 'monospace', color: color)),
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: IconButton(
            icon: Icon(icon, size: 18),
            onPressed: onTap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );
}
