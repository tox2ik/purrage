import 'dart:async';

import 'package:flutter/material.dart';

import '../state/workspace.dart';
import 'app_keys.dart';
import 'browse_view.dart';
import 'changes_view.dart';
import 'console_view.dart';
import 'debug_bar.dart';
import 'help_view.dart';
import 'ignore_dialog.dart';
import 'mode_rail.dart';
import 'notice_bar.dart';
import 'settings_view.dart';
import 'window_title.dart';

export 'mode_rail.dart' show Mode;

/// The window shell: the mode rail, the shown mode, and every app-wide key.
///
/// The work is in [Workspace]; this class holds focus, text controllers, keys
/// and layout, and owns the workspace it is given (it disposes it). Keys are
/// `Shortcuts` built from `app_keys.dart` and `Actions` that call the
/// workspace.
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
  final FocusNode listFocus = FocusNode(debugLabel: 'file list');
  final FocusNode railFocus = FocusNode(debugLabel: 'ignore rail');
  final FocusNode linesFocus = FocusNode(debugLabel: 'ignore lines');
  final FocusNode browseFocus = FocusNode(debugLabel: 'browse list');
  final FocusNode settingsFocus = FocusNode(debugLabel: 'editor list');
  final FocusNode consoleFocus = FocusNode(debugLabel: 'console list');
  final FocusNode helpFocus = FocusNode(debugLabel: 'help');
  Mode mode = Mode.changes;

  /// The first load, for tests that wait on it.
  late final Future<void> started;

  /// Plain-letter keys must reach a text field that has focus.
  bool get typing => typingInField();

  late final ShortcutManager _changesKeys = GatedShortcutManager(
    shortcuts: shortcutsOf([...motionBindings, ...changesBindings]),
    active: () => mode == Mode.changes && !typing,
  );

  late final ShortcutManager _plainKeys = GatedShortcutManager(
    shortcuts: shortcutsOf(plainBindings),
    active: () => !typing,
  );

  /// The Tab stops of each mode, in visual order.
  List<FocusNode> stops(Mode of) => switch (of) {
        Mode.changes => [filterFocus, listFocus, railFocus, linesFocus, commitFocus],
        Mode.browse => [browseFocus],
        Mode.settings => [settingsFocus],
        Mode.console => [consoleFocus],
        Mode.help => [helpFocus],
      };

  /// The stop that gets the keyboard when a mode is shown.
  FocusNode home(Mode of) => of == Mode.changes ? listFocus : stops(of).first;

  @override
  void initState() {
    super.initState();
    workspace.addListener(_redraw);
    started = workspace.start();
    _focusAfterFrame(listFocus);
    _nameWindow();
  }

  String? _titled;

  /// `<folder> - Purrage`: the title names the repository shown, and follows a
  /// Browse switch.
  void _nameWindow() {
    final path = workspace.repo.path;
    if (path == _titled) return;
    _titled = path;
    unawaited(WindowTitle.show(path));
  }

  /// A mode inside the IndexedStack can take focus once it is the shown one,
  /// which is after the frame that shows it.
  void _focusAfterFrame(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? node.requestFocus() : null);

  /// Tab / Shift+Tab: the next or previous stop of the shown mode, wrapping.
  /// A stop that is not on screen (the ignore pane hidden by `p` or a narrow
  /// window) is skipped.
  void nextPane(int delta) {
    final order = [for (final node in stops(mode)) if (node.context != null) node];
    final at = order.indexWhere((node) => node.hasFocus);
    final from = at < 0 ? (delta > 0 ? -1 : 0) : at;
    order[(from + delta) % order.length].requestFocus();
  }

  /// Background work started by the workspace; tests await it.
  Future<void> idle() => workspace.idle();

  /// [Workspace.open] swaps the state the views show, and the repository the
  /// title names.
  void _redraw() {
    setState(() {});
    _nameWindow();
  }

  @override
  void dispose() {
    workspace.removeListener(_redraw);
    workspace.dispose();
    _changesKeys.dispose();
    _plainKeys.dispose();
    commitController.dispose();
    commitFocus.dispose();
    filterController.dispose();
    for (final node in [filterFocus, listFocus, railFocus, linesFocus, browseFocus]) {
      node.dispose();
    }
    for (final node in [settingsFocus, consoleFocus, helpFocus, shellFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  void show(Mode next) {
    if (next == mode) return;
    setState(() => mode = next);
    // The shown mode gets the keyboard: out of the commit field, into its list.
    _focusAfterFrame(home(next));
  }

  void cycle(int delta) {
    final count = Mode.values.length;
    show(Mode.values[(mode.index + delta + count) % count]);
  }

  void move(MoveIntent intent) => intent.extend
      ? workspace.changes.extendSelection(intent.delta)
      : workspace.changes.move(intent.delta);

  /// What each intent does. Every action is one call; the work is in the
  /// workspace.
  late final Map<Type, Action<Intent>> _actions = {
    ShowModeIntent: CallbackAction<ShowModeIntent>(onInvoke: (intent) => show(intent.mode)),
    CycleModeIntent: CallbackAction<CycleModeIntent>(onInvoke: (intent) => cycle(intent.delta)),
    MoveIntent: CallbackAction<MoveIntent>(onInvoke: move),
    PaneIntent: CallbackAction<PaneIntent>(onInvoke: (intent) => nextPane(intent.delta)),
    SelectAllIntent: CallbackAction<SelectAllIntent>(onInvoke: (_) => workspace.changes.selectAll()),
    CollapseIntent: CallbackAction<CollapseIntent>(onInvoke: (_) => workspace.changes.collapseSelection()),
    ToggleRowIntent: CallbackAction<ToggleRowIntent>(onInvoke: (_) => workspace.changes.toggleFocused()),
    TrackIntent: CallbackAction<TrackIntent>(onInvoke: (_) => workspace.track()),
    UntrackIntent: CallbackAction<UntrackIntent>(onInvoke: (_) => workspace.untrack()),
    IgnoreIntent: CallbackAction<IgnoreIntent>(onInvoke: (_) => workspace.ignoreQuick()),
    IgnoreDialogIntent: CallbackAction<IgnoreDialogIntent>(onInvoke: (_) => ignoreWithDialog()),
    OpenFileIntent: CallbackAction<OpenFileIntent>(onInvoke: (_) => workspace.openFocused()),
    OpenIgnoreFileIntent: CallbackAction<OpenIgnoreFileIntent>(onInvoke: (_) => workspace.openSelectedIgnore()),
    ReloadIntent: CallbackAction<ReloadIntent>(onInvoke: (_) => workspace.reloadAll()),
    FocusFilterIntent: CallbackAction<FocusFilterIntent>(onInvoke: (_) => filterFocus.requestFocus()),
    FocusCommitIntent: CallbackAction<FocusCommitIntent>(onInvoke: (_) => commitFocus.requestFocus()),
    TogglePaneIntent: CallbackAction<TogglePaneIntent>(onInvoke: (_) => toggleIgnorePane()),
  };

  /// `p`: show or hide the ignore pane, whatever the window width decided.
  void toggleIgnorePane() => workspace.paneLayout.toggle(MediaQuery.sizeOf(context).width);

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
    await workspace.ignore(scope: choice.scope, target: choice.target);
  }

  /// The Commit button: the field empties when the commit was made, and the
  /// keys go back to the list.
  Future<void> commitNow(String summary) async {
    final ok = await workspace.commit(summary);
    if (!ok || !mounted) return;
    commitController.clear();
    listFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: shortcutsOf(appBindings),
      child: Shortcuts.manager(
        manager: _plainKeys,
        child: Shortcuts.manager(
          manager: _changesKeys,
          child: Actions(
            actions: _actions,
            child: Focus(focusNode: shellFocus, autofocus: true, child: _window()),
          ),
        ),
      ),
    );
  }

  Widget _window() => Scaffold(
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
      );

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
          listFocus: listFocus,
          railFocus: railFocus,
          linesFocus: linesFocus,
          ignoreState: workspace.ignorePane,
          onOpenIgnore: workspace.openSelectedIgnore,
          onNewIgnore: workspace.newIgnoreHere,
          onCommit: commitNow,
          paneLayout: workspace.paneLayout,
          onOpenIgnoreFile: workspace.openIgnoreFile,
        ),
        BrowseView(
          browser: workspace.browser,
          current: workspace.repo.path,
          onOpen: workspace.open,
          drives: workspace.browser.listDrives,
          focusNode: browseFocus,
        ),
        SettingsView(
          detect: workspace.editors.detect,
          chosenCommand: workspace.editorCommand ?? '',
          onChoose: workspace.chooseEditor,
          onTest: workspace.openTestFile,
          focusNode: settingsFocus,
        ),
        ConsoleView(log: workspace.console, focusNode: consoleFocus),
        HelpView(focusNode: helpFocus),
      ];
}
