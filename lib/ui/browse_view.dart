import 'dart:async';

import 'package:flutter/material.dart';

import '../state/browser.dart';
import 'app_keys.dart';
import 'filter_field.dart';
import 'theme.dart';
import 'widgets.dart';

/// The Browse mode: the directory being browsed, the repositories found below it,
/// a way up a level and, on Windows, a drive picker.
class BrowseView extends StatefulWidget {
  const BrowseView({
    super.key,
    required this.browser,
    required this.current,
    required this.onOpen,
    required this.focusNode,
    this.drives = RepoBrowser.drives,
  });

  final RepoBrowser browser;

  /// The list's keyboard stop; the shell gives it the keyboard on Alt+2.
  final FocusNode focusNode;

  /// The repository currently open, marked in the list.
  final String current;

  final ValueChanged<String> onOpen;

  /// The drive probe; tests pass one that touches no disk.
  final Future<List<String>> Function() drives;

  @override
  State<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<BrowseView> {
  List<String> drives = const [];
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocus = FocusNode(debugLabel: 'browse filter');

  RepoBrowser get browser => widget.browser;

  @override
  void initState() {
    super.initState();
    unawaited(_probeDrives());
  }

  @override
  void dispose() {
    filterController.dispose();
    filterFocus.dispose();
    super.dispose();
  }

  Future<void> _probeDrives() async {
    final found = await widget.drives();
    if (mounted) setState(() => drives = found);
  }

  /// Enter: open the repository under the cursor.
  void openSelected() {
    final path = browser.selected;
    if (path != null) widget.onOpen(path);
  }

  late final Map<Type, Action<Intent>> _actions = {
    MoveIntent: CallbackAction<MoveIntent>(onInvoke: (intent) => browser.move(intent.delta)),
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => openSelected()),
    UpIntent: CallbackAction<UpIntent>(onInvoke: (_) => browser.up()),
    ReloadIntent: CallbackAction<ReloadIntent>(onInvoke: (_) => browser.rescan()),
    FocusFilterIntent: CallbackAction<FocusFilterIntent>(onInvoke: (_) => filterFocus.requestFocus()),
  };

  @override
  Widget build(BuildContext context) {
    return KeyScope(
      bindings: const [...motionBindings, ...browseBindings],
      actions: _actions,
      focusNode: widget.focusNode,
      child: ListenableBuilder(
        listenable: browser,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(browser: browser, drives: drives),
            FilterField(
              controller: filterController,
              focusNode: filterFocus,
              onChanged: browser.setFilter,
              onDone: widget.focusNode.requestFocus,
            ),
            const Divider(height: 1),
            Expanded(child: _List(browser: browser, current: widget.current, onOpen: widget.onOpen)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.browser, required this.drives});

  final RepoBrowser browser;
  final List<String> drives;

  @override
  Widget build(BuildContext context) {
    final mono = T.codeSmall.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, T.gap8, 10, T.gap8),
      child: Row(
        children: [
          IconAction(icon: Icons.arrow_upward, tooltip: 'Up one level (Backspace or h)', onPressed: browser.up),
          const SizedBox(width: T.gap4),
          IconAction(
            icon: Icons.refresh,
            tooltip: 'Scan this directory again (F5 or Ctrl+R)',
            onPressed: browser.rescan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(browser.directory, overflow: TextOverflow.ellipsis, maxLines: 1, style: mono),
          ),
          if (browser.scanning) ...[
            const SizedBox(width: 10),
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
          if (drives.isNotEmpty) ...[
            const SizedBox(width: 10),
            _DrivePicker(drives: drives, onPicked: browser.goTo),
          ],
          const SizedBox(width: 8),
          Text('${browser.repos.length} repo(s)', style: mono),
        ],
      ),
    );
  }
}

/// The drive picker, in the role of a `DropdownButton`: its label "Drive" is
/// the button, so clicking the word opens the menu.
class _DrivePicker extends StatelessWidget {
  const _DrivePicker({required this.drives, required this.onPicked});

  final List<String> drives;
  final ValueChanged<String> onPicked;

  void _picked(String? root) {
    if (root != null) onPicked(root);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Clickable(
      tooltip: 'Switch drive',
      child: DropdownButton<String>(
        value: null,
        hint: Text('Drive', style: T.small.copyWith(color: scheme.onSurfaceVariant)),
        isDense: true,
        underline: const SizedBox.shrink(),
        padding: EdgeInsets.zero,
        items: [
          for (final root in drives)
            DropdownMenuItem(
              value: root,
              child: Text(root.substring(0, 2), style: T.small.copyWith(color: scheme.onSurface)),
            ),
        ],
        onChanged: _picked,
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.browser, required this.current, required this.onOpen});

  final RepoBrowser browser;
  final String current;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final shown = browser.visible;
    if (shown.isEmpty) {
      final empty = browser.repos.isNotEmpty
          ? 'No repository matches "${browser.filter}".'
          : browser.scanning
              ? 'Scanning…'
              : 'No git repository within five levels.';
      return Center(child: Text(empty, textAlign: TextAlign.center));
    }
    final open = current.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
    final cursor = browser.index;
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (context, index) => RepoRow(
        path: shown[index],
        isCurrent: shown[index].toLowerCase() == open.toLowerCase(),
        focused: index == cursor,
        onTap: () => onOpen(shown[index]),
      ),
    );
  }
}

/// One repository in the Browse list: the same two columns as a file row, the
/// folder right-aligned and the name left-aligned, so names line up.
class RepoRow extends StatelessWidget {
  const RepoRow({
    super.key,
    required this.path,
    required this.isCurrent,
    required this.onTap,
    this.focused = false,
  });

  final String path;
  final bool isCurrent;
  final VoidCallback onTap;

  /// The keyboard cursor is on this row.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clean = path.replaceAll(r'\', '/');
    final name = clean.split('/').last;
    final parent = clean.length > name.length ? clean.substring(0, clean.length - name.length - 1) : '';
    return HoverRow(
      tooltip: isCurrent ? 'Already open: $path' : 'Open $path',
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(T.gap8, T.gap2, T.gap12, T.gap2),
      decoration: BoxDecoration(
        color: isCurrent
            ? T.current
            : focused
                ? T.cursor
                : null,
        border: Border(
          left: BorderSide(width: T.barWidth, color: isCurrent || focused ? scheme.primary : T.none),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _FolderCell(parent: parent)),
          const SizedBox(width: T.gap6),
          Expanded(flex: 3, child: _NameCell(name: name, isCurrent: isCurrent)),
        ],
      ),
    );
  }
}

class _FolderCell extends StatelessWidget {
  const _FolderCell({required this.parent});

  final String parent;

  @override
  Widget build(BuildContext context) => Text(
        parent.isEmpty ? '' : '$parent/',
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: T.codeSmall.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.name, required this.isCurrent});

  final String name;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: T.body.copyWith(color: T.folder),
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: T.gap6),
            Text('open', style: T.tiny.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
        ],
      );
}
