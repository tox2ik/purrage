import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/changes.dart';
import '../state/status.dart';
import 'changes_view.dart';
import 'filter_field.dart';
import 'theme.dart';
import 'widgets.dart';

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
    required this.onReload,
    required this.filterController,
    required this.filterFocus,
  });

  final Changes changes;
  final VoidCallback onIgnore;
  final VoidCallback onQuickIgnore;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onOpen;
  final VoidCallback onReload;
  final TextEditingController filterController;
  final FocusNode filterFocus;

  @override
  State<FileList> createState() => _FileListState();
}

class _FileListState extends State<FileList> {
  final ScrollController scroll = ScrollController();
  final Map<int, GlobalKey> keys = {};

  Changes get changes => widget.changes;

  @override
  void initState() {
    super.initState();
    changes.addListener(_reveal);
  }

  @override
  void dispose() {
    changes.removeListener(_reveal);
    scroll.dispose();
    super.dispose();
  }

  /// Keep the focused row on screen after a move.
  void _reveal() {
    final target = keys[changes.index]?.currentContext;
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

  // The row buttons act on their row, or on the selection when the row is in
  // it: that rule is `Changes.target`, not the view's.
  void _track(int index) => _onRow(index, widget.onTrack);
  void _untrack(int index) => _onRow(index, widget.onUntrack);
  void _ignore(int index) => _onRow(index, widget.onIgnore);
  void _quickIgnore(int index) => _onRow(index, widget.onQuickIgnore);

  void _onRow(int index, VoidCallback action) {
    changes.target(index);
    action();
  }

  /// A double click opens the row it is on, whatever was selected.
  void _open(int index) {
    changes.click(index);
    widget.onOpen();
  }

  void _tap(int index) {
    final keyboard = HardwareKeyboard.instance;
    changes.click(index, ctrl: keyboard.isControlPressed, shift: keyboard.isShiftPressed);
  }

  @override
  Widget build(BuildContext context) {
    final header = _Header(
      filter: FilterField(
        controller: widget.filterController,
        focusNode: widget.filterFocus,
        onChanged: changes.setFilter,
      ),
      onReload: widget.onReload,
    );
    return Column(
      children: [
        header,
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (changes.rows.isEmpty) {
      return const Center(child: Text('Nothing to commit, working tree clean.'));
    }
    if (changes.visible.isEmpty) {
      return Center(child: Text('No path matches "${changes.filter}".'));
    }
    // A flat list of headers and rows, built lazily: several hundred paths must
    // not rebuild every tile for one cursor move.
    final items = flatItems(changes);
    return Listener(
      onPointerSignal: _wheel,
      child: ListView.builder(
        controller: scroll,
        itemCount: items.length,
        itemBuilder: (context, at) => _item(items[at]),
      ),
    );
  }

  Widget _item(Object item) {
    if (item is SectionHeader) return item;
    final index = (item as RowEntry).index;
    final row = item.row;
    return FileRow(
      key: keys[index] ??= GlobalKey(),
      row: row,
      focused: index == changes.index,
      chosen: changes.isSelected(row),
      nested: changes.isNested(row),
      onTap: () => _tap(index),
      onTrack: () => _track(index),
      onUntrack: () => _untrack(index),
      onIgnore: () => _ignore(index),
      onQuickIgnore: () => _quickIgnore(index),
      onOpen: () => _open(index),
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
    GestureBinding.instance.pointerSignalResolver.register(event, (_) => changes.move(dy > 0 ? 5 : -5));
  }
}

/// The list as the builder walks it: a [SectionHeader] before each non-empty
/// section, then a [RowEntry] per row with its index in `changes.visible`.
List<Object> flatItems(Changes changes) {
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
  return items;
}

/// One file row: status letter, folder, the actions, then the name.
///
/// `chosen` is the selection (Ctrl/Shift clicks build it); `focused` is the
/// cursor. They draw differently so a multi-selection still shows where the
/// cursor is.
class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.row,
    required this.focused,
    required this.chosen,
    required this.nested,
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
  final bool nested;
  final VoidCallback onTap;
  final VoidCallback onTrack;
  final VoidCallback onUntrack;
  final VoidCallback onIgnore;
  final VoidCallback onQuickIgnore;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return HoverRow(
      tooltip: _tooltip,
      onTap: onTap,
      onSecondaryTap: onIgnore,
      onDoubleTap: onOpen,
      padding: const EdgeInsets.fromLTRB(9, 2, 8, 2),
      decoration: BoxDecoration(
        color: chosen
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : focused
                ? scheme.secondaryContainer.withValues(alpha: 0.35)
                : null,
        border: Border(
          left: BorderSide(width: 3, color: focused ? scheme.primary : Colors.transparent),
        ),
      ),
      child: _cells(scheme),
    );
  }

  /// Folder first, then the actions, then the name, each in a fixed share of
  /// the row, so the names line up whatever the folder depths are.
  Widget _cells(ColorScheme scheme) => Row(
        children: [
          _Badge(text: _badge, color: chosen ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(flex: 2, child: _FolderCell(folder: row.folder)),
          const SizedBox(width: 6),
          _RowActions(
            staged: row.isStaged,
            conflict: row.isConflict,
            onTrack: onTrack,
            onUntrack: onUntrack,
            onIgnore: onQuickIgnore,
          ),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: _NameCell(row: row, chosen: chosen, nested: nested)),
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

class _FolderCell extends StatelessWidget {
  const _FolderCell({required this.folder});

  final String folder;

  @override
  Widget build(BuildContext context) => Text(
        folder.isEmpty ? '' : '$folder/',
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
              fontSize: 11.5,
            ),
      );
}

/// The base name, and the `git` marker when its folder is a repository of its
/// own: the marker belongs to the name, not to a column of its own.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.row, required this.chosen, required this.nested});

  final StatusRow row;
  final bool chosen;
  final bool nested;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: _style(Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          if (nested) ...[
            const SizedBox(width: 5),
            const Pill(
              'git',
              tooltip: 'Nested git repository: its ignore rules live in its own .gitignore',
            ),
          ],
        ],
      );

  /// A directory takes Windows Explorer's folder colour, so a folder reads as a
  /// folder at a glance; a chosen row is bold on top of that.
  TextStyle? _style(TextStyle? style) {
    var out = style;
    if (row.path.endsWith('/')) out = out?.copyWith(color: purrageFolder);
    if (chosen) out = out?.copyWith(fontWeight: FontWeight.w600);
    return out;
  }
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
          LinkButton(
            label: staged ? 'Untrack' : 'Add',
            tooltip: staged ? 'Stop tracking this file (u)' : 'Track this file, git add (a)',
            onTap: staged ? onUntrack : onTrack,
            width: 52,
          ),
        const SizedBox(width: 4),
        LinkButton(
          label: 'Ignore',
          tooltip: 'Add the literal path to the root .gitignore (i)',
          onTap: onIgnore,
          width: 48,
        ),
      ],
    );
  }
}

/// The top of the list pane: the filter field, and a reload button that does what
/// F5 does. The button lives right after the field, in the same strip.
class _Header extends StatelessWidget {
  const _Header({required this.filter, required this.onReload});

  final Widget filter;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: filter),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconAction(icon: Icons.refresh, tooltip: 'Re-read the state (F5)', onPressed: onReload),
          ),
        ],
      );
}

/// One row in the flat list the builder walks.
class RowEntry {
  const RowEntry({required this.row, required this.index});

  final StatusRow row;
  final int index;
}
