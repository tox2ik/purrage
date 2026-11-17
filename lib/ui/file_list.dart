import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.onQuickIgnore,
    required this.onTrack,
    required this.onUntrack,
    required this.onOpen,
    required this.filterController,
    required this.filterFocus,
  });

  final Changes changes;
  final VoidCallback onIgnore;
  final VoidCallback onQuickIgnore;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onOpen;
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
    final target = keys[index]?.currentContext;
    if (target == null) return;
    final rowBox = target.findRenderObject();
    final listBox = scroll.position.context.storageContext.findRenderObject();
    if (rowBox is RenderBox && listBox is RenderBox && rowBox.hasSize && listBox.hasSize) {
      final offset = rowBox.localToGlobal(Offset.zero, ancestor: listBox);
      final bottom = offset.dy + rowBox.size.height;
      // Already in view: do not scroll. Centring every move is what made the
      // list feel like it was dragging behind the cursor.
      if (offset.dy >= 0 && bottom <= listBox.size.height) return;
    }
    Scrollable.ensureVisible(target, alignment: 0.5, duration: const Duration(milliseconds: 90));
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
    // A flat list of headers and rows, built lazily: several hundred paths must
    // not rebuild every tile for one cursor move.
    final items = <Object>[];
    var flat = 0;
    for (final section in Section.values) {
      final rows = changes.section(section);
      if (rows.isEmpty) continue;
      items.add(SectionHeader(section: section, count: rows.length));
      for (final row in rows) {
        items.add(RowEntry(row: row, index: flat++));
      }
    }
    return Column(
      children: [
        filter,
        Expanded(
          child: Listener(
            onPointerSignal: _wheel,
            child: ListView.builder(
              controller: scroll,
              itemCount: items.length,
              itemBuilder: (context, at) => _item(context, items[at], changes),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, Object item, Changes changes) {
    if (item is SectionHeader) return item;
    final entry = item as RowEntry;
    final index = entry.index;
    final row = entry.row;
    keys[index] ??= GlobalKey();
    return RowTile(
      key: keys[index],
      row: row,
      focused: index == changes.index,
      chosen: changes.isSelected(row),
      onTap: (ctrl, shift) => changes.click(index, ctrl: ctrl, shift: shift),
      onTrack: () {
        if (!changes.isSelected(row)) changes.click(index);
        widget.onTrack();
      },
      onUntrack: () {
        if (!changes.isSelected(row)) changes.click(index);
        widget.onUntrack();
      },
      onIgnore: () {
        if (!changes.isSelected(row)) changes.click(index);
        widget.onIgnore();
      },
      onQuickIgnore: () {
        if (!changes.isSelected(row)) changes.click(index);
        widget.onQuickIgnore();
      },
      onOpen: () {
        changes.click(index);
        widget.onOpen();
      },
    );
  }

  /// Shift + wheel steps the cursor five rows at a time instead of scrolling,
  /// the way Ops' wheel mode steps through items. Claiming the signal keeps the
  /// list from scrolling underneath.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!HardwareKeyboard.instance.isShiftPressed) return;
    final dy = event.scrollDelta.dy != 0 ? event.scrollDelta.dy : event.scrollDelta.dx;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      widget.changes.move(dy > 0 ? 5 : -5);
    });
  }
}

/// One file row: status letter, folder, name, and the actions at the end.
///
/// `chosen` is the selection (Ctrl/Shift clicks build it); `focused` is the
/// cursor. They draw differently so a multi-selection still shows where the
/// cursor is.
class RowTile extends StatelessWidget {
  const RowTile({
    super.key,
    required this.row,
    required this.focused,
    required this.chosen,
    required this.onTap,
    required this.onTrack,
    required this.onUntrack,
    required this.onIgnore,
    required this.onQuickIgnore,
    required this.onOpen,
  });

  final StatusRow row;
  final bool focused;
  final bool chosen;
  final void Function(bool ctrl, bool shift) onTap;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onIgnore;
  final VoidCallback onQuickIgnore;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    final keyboard = HardwareKeyboard.instance;
    return Tooltip(
      message: _tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: () => onTap(keyboard.isControlPressed, keyboard.isShiftPressed),
          onSecondaryTap: onIgnore,
          onDoubleTap: onOpen,
          child: Container(
            decoration: BoxDecoration(
              color: chosen
                  ? scheme.primaryContainer.withValues(alpha: 0.55)
                  : focused
                      ? scheme.secondaryContainer.withValues(alpha: 0.35)
                      : null,
              border: Border(
                left: BorderSide(
                  width: 3,
                  color: focused ? scheme.primary : Colors.transparent,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(9, 2, 8, 2),
            child: Row(
              children: [
                _Badge(text: _badge, color: chosen ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(child: _name(style, scheme, chosen)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Folder first, then the name, each in a fixed share of the row, so the file
  /// names line up under each other whatever the folder depths are.
  Widget _name(TextStyle? style, ColorScheme scheme, bool chosen) => Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              row.folder.isEmpty ? '' : '${row.folder}/',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: style?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'monospace', fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 6),
          _RowActions(
            staged: row.isStaged,
            conflict: row.isConflict,
            onTrack: onTrack,
            onUntrack: onUntrack,
            onIgnore: onQuickIgnore,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: chosen ? style?.copyWith(fontWeight: FontWeight.w600) : style,
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
        width: 12,
        child: Text(text, style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: color)),
      );
}

/// The two row actions, as text: `Add` (or `Untrack`) and `Ignore`, in a fixed
/// slot between the folder and the name so the names still line up.
class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.staged,
    required this.conflict,
    required this.onTrack,
    required this.onUntrack,
    required this.onIgnore,
  });

  final bool staged;
  final bool conflict;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!conflict)
          _TextAction(
            label: staged ? 'Untrack' : 'Add',
            tooltip: staged ? 'Stop tracking this file' : 'Track this file (git add)',
            onTap: staged ? onUntrack : onTrack,
            width: 52,
          ),
        const SizedBox(width: 4),
        _TextAction(
          label: 'Ignore',
          tooltip: 'Add the literal path to the root .gitignore',
          onTap: onIgnore,
          width: 48,
        ),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.width,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: width,
          height: 20,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the flat list the builder walks.
class RowEntry {
  const RowEntry({required this.row, required this.index});

  final StatusRow row;
  final int index;
}
