import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/workspace.dart';
import 'browse_view.dart';
import 'changes_view.dart';
import 'console_view.dart';
import 'debug_bar.dart';
import 'help_view.dart';
import 'ignore_dialog.dart';
import 'mode_rail.dart';
import 'nav_keys.dart';
import 'notice_bar.dart';
import 'settings_view.dart';

export 'mode_rail.dart' show Mode;

/// The window shell: the mode rail, the shown mode, and every app-wide key.
///
/// The work is in [Workspace]; this class holds focus, text controllers, keys
/// and layout, and owns the workspace it is given (it disposes it).
class Shell extends StatefulWidget {
  const Shell({super.key, required this.workspace});

  final Workspace workspace;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  Workspace get workspace => widget.workspace;

  final FocusNode shellFocus = FocusNode(debugLabel: 'shell');
  final TextEditingController commitController = TextEditingController();
  final FocusNode commitFocus = FocusNode(debugLabel: 'commit message');
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocus = FocusNode(debugLabel: 'filter');
  Mode mode = Mode.changes;

  /// The first load, for tests that wait on it.
  late final Future<void> started;

  @override
  void initState() {
    super.initState();
    workspace.addListener(_redraw);
    started = workspace.start();
  }

  /// Background work started by the workspace; tests await it.
  Future<void> idle() => workspace.idle();

  /// [Workspace.open] swaps the state the views show.
  void _redraw() => setState(() {});

  @override
  void dispose() {
    workspace.removeListener(_redraw);
    workspace.dispose();
    commitController.dispose();
    commitFocus.dispose();
    filterController.dispose();
    filterFocus.dispose();
    shellFocus.dispose();
    super.dispose();
  }

  void show(Mode next) {
    if (next == mode) return;
    setState(() => mode = next);
    // Leaving Changes takes the keyboard out of the commit field.
    if (next != Mode.changes) commitFocus.unfocus();
    shellFocus.requestFocus();
  }

  void cycle(int delta) {
    final count = Mode.values.length;
    show(Mode.values[(mode.index + delta + count) % count]);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isAltPressed && _altKey(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (event.character == '?' && isPlain(event)) {
      show(Mode.help);
      return KeyEventResult.handled;
    }
    if (mode != Mode.changes || commitFocus.hasFocus || filterFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    return _changesKey(event);
  }

  bool _altKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.bracketRight) {
      cycle(1);
    } else if (key == LogicalKeyboardKey.bracketLeft) {
      cycle(-1);
    } else {
      final picked = Mode.values.where((mode) => mode.digit == key);
      if (picked.isEmpty) return false;
      show(picked.first);
    }
    return true;
  }

  KeyEventResult _changesKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    final changes = workspace.changes;
    // F5 and Ctrl+R: ask git again and redraw the list, the desktop habit.
    if (event.logicalKey == LogicalKeyboardKey.f5 ||
        (keyboard.isControlPressed && event.character?.toLowerCase() == 'r')) {
      workspace.reloadAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && keyboard.isControlPressed) {
      changes.toggleFocused();
      return KeyEventResult.handled;
    }
    final delta = navDelta(event);
    if (delta != null) {
      keyboard.isShiftPressed ? changes.extendSelection(delta) : changes.move(delta);
      return KeyEventResult.handled;
    }
    // Ctrl+F is the desktop habit for the same field.
    if (keyboard.isControlPressed && event.character?.toLowerCase() == 'f') {
      filterFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (!isPlain(event)) return KeyEventResult.ignored;
    final action = _plainKeys[event.character] ?? _plainKeys[event.character?.toLowerCase()];
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  /// The plain keys of the Changes list; an exact match (`I`, `E`) wins over
  /// its lower-case key.
  late final Map<String, VoidCallback> _plainKeys = {
    '/': filterFocus.requestFocus,
    'I': ignoreWithDialog,
    'E': workspace.openSelectedIgnore,
    'i': workspace.ignoreQuick,
    ' ': workspace.track,
    'a': workspace.track,
    'u': workspace.untrack,
    'e': workspace.openFocused,
    'r': workspace.reloadAll,
    'c': commitFocus.requestFocus,
  };

  /// Shift+I: ask how wide the rule is and where it goes, then write it. The
  /// dialog is the UI's part; the workspace asks and writes.
  Future<void> ignoreWithDialog() async {
    final question = await workspace.ignoreQuestion();
    if (question == null || !mounted) return;
    final choice = await IgnoreDialog.show(
      context,
      changes: workspace.changes,
      row: question.row,
      targets: question.targets,
    );
    if (choice == null || !mounted) return;
    await workspace.ignore(
      scope: choice.scope,
      target: choice.target,
      stopTracking: choice.stopTracking,
    );
  }

  /// The Commit button: the field empties when the commit was made.
  Future<void> commitNow(String summary) async {
    final ok = await workspace.commit(summary);
    if (ok && mounted) commitController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: shellFocus,
      autofocus: true,
      onKeyEvent: onKey,
      child: Scaffold(
        body: Stack(
          children: [
            DebugBar(roles: appFocusRoles, child: _layout()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 74,
              child: Center(child: NoticeBar(notices: workspace.notices)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layout() => Row(
        children: [
          ModeRail(current: mode, onPick: show),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: mode.index, children: _modes())),
        ],
      );

  List<Widget> _modes() => [
        ChangesView(
          changes: workspace.changes,
          commitController: commitController,
          commitFocus: commitFocus,
          onIgnore: ignoreWithDialog,
          onQuickIgnore: workspace.ignoreQuick,
          onTrack: workspace.track,
          onUntrack: workspace.untrack,
          onOpen: workspace.openFocused,
          onReload: workspace.reloadAll,
          filterController: filterController,
          filterFocus: filterFocus,
          ignoreState: workspace.ignorePane,
          onOpenIgnore: workspace.openSelectedIgnore,
          onNewIgnore: workspace.newIgnoreHere,
          onCommit: commitNow,
        ),
        BrowseView(browser: workspace.browser, current: workspace.repo.path, onOpen: workspace.open),
        SettingsView(
          detect: workspace.editors.detect,
          chosenCommand: workspace.editorCommand ?? '',
          onChoose: workspace.chooseEditor,
          onTest: workspace.openTestFile,
        ),
        ConsoleView(log: workspace.console),
        const HelpView(),
      ];
}
