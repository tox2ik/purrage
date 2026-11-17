import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/browser.dart';
import '../state/changes.dart';
import '../state/console.dart';
import '../state/diagnostics.dart';
import '../state/editors.dart';
import '../state/failure.dart';
import '../state/git_repo.dart';
import '../state/ignore_files.dart';
import '../state/notices.dart';
import '../state/prefs.dart';
import '../state/repo.dart';
import 'changes_view.dart';
import 'browse_view.dart';
import 'console_view.dart';
import 'debug_bar.dart';
import 'help_view.dart';
import 'ignore_dialog.dart';
import 'nav_keys.dart';
import 'notice_bar.dart';
import 'settings_view.dart';

/// The modes the app shows; the rail lists them in this order.
enum Mode { changes, browse, settings, console, help }

extension on Mode {
  String get label => switch (this) {
        Mode.changes => 'Changes',
        Mode.browse => 'Browse',
        Mode.settings => 'Settings',
        Mode.console => 'Console',
        Mode.help => 'Help',
      };
  IconData get icon => switch (this) {
        Mode.changes => Icons.description_outlined,
        Mode.browse => Icons.folder_open_outlined,
        Mode.settings => Icons.settings_outlined,
        Mode.console => Icons.terminal,
        Mode.help => Icons.help_outline,
      };
}

/// The window shell: the mode rail, the shown mode, and every app-wide key.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.repo, this.seeded, this.console});

  final GitRepo repo;

  /// A prepared state, for tests: the fake repo path never touches git.
  final Changes? seeded;

  /// The app-wide console, shared with the error handlers; tests may omit it.
  final ConsoleLog? console;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  /// The repository being shown; Browse can replace it.
  late GitRepo repo = widget.repo;
  late Changes changes = widget.seeded ?? Changes(repo);
  late RepoBrowser browser = RepoBrowser(startDirectory: repo.path);
  final FocusNode shellFocus = FocusNode(debugLabel: 'shell');
  final TextEditingController commitController = TextEditingController();
  final FocusNode commitFocus = FocusNode(debugLabel: 'commit message');
  final TextEditingController filterController = TextEditingController();
  final FocusNode filterFocus = FocusNode(debugLabel: 'filter');
  final Prefs prefs = Prefs();
  late final Editors editors = Editors(prefs: prefs);
  late IgnorePaneState ignorePane = IgnorePaneState(repo);
  final Notices notices = Notices();
  late final ConsoleLog console = widget.console ?? ConsoleLog();
  /// The ignore pane's highlight asks git, so it waits for the cursor to settle.
  Timer? ignoreProbe;
  String? editorCommand;
  Mode mode = Mode.changes;

  @override
  void initState() {
    super.initState();
    changes.addListener(onChangesChanged);
    loadEverything();
    // The Browse list is wanted as soon as the window is up, so it scans in the
    // background rather than on the frame that shows the changes.
    unawaited(browser.scan());
    prefs.load().then((_) {
      if (mounted) setState(() => editorCommand = prefs.editorCommand);
    });
  }

  /// Browse: open another repository, which means new state for everything that
  /// is tied to the old one.
  Future<void> openRepository(String path) async {
    if (widget.seeded != null) {
      say('this session was seeded with a repository; Browse cannot switch it');
      return;
    }
    Diagnostics.enter('Browse: open $path');
    console.add(
      ActionFailure.done(
        summary: 'opening $path',
        detail: 'origin: Shell.openRepository\nclicked in the Browse list',
        origin: 'Shell.openRepository',
      ),
      action: 'browse',
    );
    try {
      final opened = await Repo.open(path);
      final next = Changes(opened);
      await next.load();
      final pane = IgnorePaneState(opened);
      if (!mounted) return;
      changes.removeListener(onChangesChanged);
      changes.dispose();
      ignorePane.dispose();
      setState(() {
        repo = opened;
        changes = next;
        ignorePane = pane;
        // Stay in Browse: the click marks the new checkout, and Changes is one
        // key away. Jumping modes on a click made the switch look like nothing.
      });
      changes.addListener(onChangesChanged);
      await loadEverything();
      browser.directory = opened.path;
      unawaited(browser.scan());
      console.add(
        ActionFailure.done(
          summary: 'opened ${opened.path}',
          detail: 'origin: Shell.openRepository -> Repo.open\ncwd: ${opened.path}'
              '\nrows: ${changes.visible.length}',
          origin: 'Shell.openRepository',
        ),
        action: 'browse',
      );
    } on Exception catch (error) {
      say(
        'cannot open $path',
        failure: ActionFailure.fromError(error, origin: 'Shell.openRepository -> Repo.open', params: {'path': path}),
        action: 'browse',
      );
    } finally {
      Diagnostics.leave();
    }
  }

  @override
  void dispose() {
    changes.removeListener(onChangesChanged);
    ignoreProbe?.cancel();
    ignorePane.dispose();
    notices.dispose();
    if (widget.console == null) console.dispose();
    changes.dispose();
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
    if (next != Mode.changes) {
      // Leaving Changes takes the keyboard out of the commit field.
      commitFocus.unfocus();
    }
    shellFocus.requestFocus();
  }

  void cycle(int delta) {
    final modes = Mode.values;
    final next = (mode.index + delta) % modes.length;
    show(modes[next < 0 ? next + modes.length : next]);
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;

    if (keyboard.isAltPressed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.bracketRight) {
        cycle(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.bracketLeft) {
        cycle(-1);
        return KeyEventResult.handled;
      }
      for (final entry in _altDigits.entries) {
        if (key == entry.value) {
          show(entry.key);
          return KeyEventResult.handled;
        }
      }
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

  KeyEventResult _changesKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    // F5 and Ctrl+R: ask git again and redraw the list, the desktop habit.
    if (event.logicalKey == LogicalKeyboardKey.f5 ||
        (keyboard.isControlPressed && event.character?.toLowerCase() == 'r')) {
      reloadAll();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && keyboard.isControlPressed) {
      changes.toggleFocused();
      return KeyEventResult.handled;
    }
    final delta = navDelta(event);
    if (delta != null) {
      if (keyboard.isShiftPressed) {
        changes.extendSelection(delta);
      } else {
        changes.move(delta);
      }
      return KeyEventResult.handled;
    }
    // Ctrl+F is the desktop habit for the same field.
    if (keyboard.isControlPressed && event.character?.toLowerCase() == 'f') {
      filterFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (!isPlain(event)) return KeyEventResult.ignored;
    if (event.character == '/') {
      filterFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.character == 'I') {
      ignoreSelectedRow();
      return KeyEventResult.handled;
    }
    if (event.character == 'E') {
      openSelectedIgnore();
      return KeyEventResult.handled;
    }
    if (event.character?.toLowerCase() == 'i') {
      ignoreQuick();
      return KeyEventResult.handled;
    }
    switch (event.character?.toLowerCase()) {
      case ' ':
      case 'a':
        trackSel();
      case 'u':
        untrackSel();
      case 'e':
        openFocusedFile();
      case 'r':
        reloadAll();
      case 'c':
        commitFocus.requestFocus();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The Commit button: one summary line, reported like every other action.
  Future<void> commitNow(String summary) async {
    Diagnostics.enter('Changes: commit');
    try {
      final ok = await changes.commit(summary);
      if (!mounted) return;
      if (ok) {
        commitController.clear();
        report('commit');
      } else {
        say(
          changes.error ?? 'commit failed',
          failure: changes.lastFailure,
          action: 'commit',
        );
      }
    } finally {
      Diagnostics.leave();
    }
  }

  /// `space` / `a`: stage the highlighted rows. The rows move to Staged at once;
  /// a failure comes back as a notice and the list is put right again. Either
  /// way the console gets the command that ran.
  Future<void> trackSel() async {
    Diagnostics.enter('Changes: track (${changes.selectionCount} selected)');
    try {
      final problem = await changes.trackSelected();
      if (!mounted) return;
      report('track', problem: problem);
    } finally {
      Diagnostics.leave();
    }
  }

  /// `u`: stop tracking the highlighted rows, at once.
  Future<void> untrackSel() async {
    Diagnostics.enter('Changes: untrack (${changes.selectionCount} selected)');
    try {
      final problem = await changes.untrackSelected();
      if (!mounted) return;
      report('untrack', problem: problem);
    } finally {
      Diagnostics.leave();
    }
  }

  /// One place for the console: every add, untrack and ignore lands here, with
  /// the command line and the working directory, whether it worked or not.
  void report(String action, {String? problem}) {
    if (problem != null) {
      say(problem, failure: changes.lastFailure, action: action);
      return;
    }
    final verb = switch (action) {
      'track' => 'tracked',
      'untrack' => 'stopped tracking',
      'ignore' => 'ignored',
      _ => action,
    };
    final files = changes.lastChanged == 1 ? '1 file' : '${changes.lastChanged} files';
    console.add(
      ActionFailure.done(
        summary: '$verb $files',
        detail: [
          'origin: ${changes.lastOrigin ?? '-'}',
          'changed: ${changes.lastChanged}',
          'cwd: ${repo.path}',
          if (changes.lastCommand != null) 'command: ${changes.lastCommand}',
        ].join('\n'),
        origin: changes.lastOrigin,
      ),
      action: action,
    );
  }

  /// `e`: open the focused file in the chosen editor.
  Future<void> openFocusedFile() async {
    final row = changes.selected;
    if (row == null) {
      say('nothing selected to open');
      return;
    }
    if (row.path.endsWith('/')) {
      say('${row.path} is a folder');
      return;
    }
    try {
      await editors.open(file: '${repo.path}/${row.path}');
    } on EditorException catch (error) {
      say(
        error.message,
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.openFocusedFile -> Editors.open',
          params: {'file': row.path},
        ),
        action: 'open',
      );
    }
  }

  /// One key: ignore the focused rows with their literal path in the root
  /// .gitignore. The rows leaving the list is the feedback; only a refusal or a
  /// failure is said out loud.
  Future<void> ignoreQuick() async {
    Diagnostics.enter('Changes: ignore, literal path (${changes.selectionCount} selected)');
    try {
      final problem = await changes.ignoreQuick();
      await reloadIgnorePane();
      if (!mounted) return;
      report('ignore', problem: problem);
    } on Exception catch (error) {
      say(
        'ignore failed',
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.ignoreQuick',
          params: {'selected': changes.selectionCount},
        ),
        action: 'ignore',
      );
    } finally {
      Diagnostics.leave();
    }
  }

  /// Shift+I: ask how wide the rule is and where it goes, then write it.
  ///
  /// A silent early return is what makes an ignore that did nothing look
  /// intentional, so failures are always said; a success is not.
  Future<void> ignoreSelectedRow() async {
    final row = changes.selected;
    if (row == null) {
      say('nothing selected to ignore');
      return;
    }
    Diagnostics.enter('Changes: ignore dialog for ${row.path}');
    try {
      final targets = await changes.ignoreTargets();
      if (!mounted) return;
      if (targets.isEmpty) {
        say('no ignore file to write to for ${row.path}');
        return;
      }
      final choice = await IgnoreDialog.show(context, changes: changes, row: row, targets: targets);
      if (choice == null || !mounted) return;
      final problem = await changes.ignoreSelected(
        scope: choice.scope,
        target: choice.target,
        stopTracking: choice.stopTracking,
      );
      await reloadIgnorePane();
      if (!mounted) return;
      report('ignore', problem: problem);
    } on Exception catch (error) {
      say(
        'ignore failed',
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.ignoreSelectedRow',
          params: {'row': row.path},
        ),
        action: 'ignore',
      );
    } finally {
      Diagnostics.leave();
    }
  }

  /// The one place a failure is reported: a notice that stays while the mouse is
  /// over it, and a row in the Console mode with the full story. A success says
  /// nothing.
  void say(String message, {ActionFailure? failure, String? action}) {
    if (!mounted) return;
    notices.show(message);
    console.add(
      failure ??
          ActionFailure(
            summary: message,
            detail: 'origin: Shell.say\nmessage: $message',
            origin: 'Shell.say',
          ),
      action: action,
    );
  }

  /// The first load touches git twice: the status and the ignore files, then the
  /// highlight for whichever row ends up focused.
  Future<void> loadEverything() => reloadAll();

  /// Re-read everything an action can change: the status list, the ignore files
  /// and the highlight. The r key, F5 and Ctrl+R call this.
  Future<void> reloadAll() async {
    await changes.load();
    await reloadIgnorePane();
  }

  /// The ignore files alone: after an ignore action they are what changed.
  Future<void> reloadIgnorePane() async {
    await ignorePane.load();
    syncIgnoreFocus();
  }

  /// A move redraws the list; the ignore pane's git check-ignore runs only
  /// once the cursor has been still for a moment, so holding a key never waits
  /// on a subprocess.
  void onChangesChanged() {
    ignoreProbe?.cancel();
    ignoreProbe = Timer(const Duration(milliseconds: 250), syncIgnoreFocus);
  }

  /// Keep the ignore pane's highlight on the focused row.
  void syncIgnoreFocus() {
    final path = changes.selected?.path;
    if (path == null) return;
    ignorePane.focusPath(path);
  }

  Future<void> chooseEditor(String? command) async {
    await prefs.setEditorCommand(command);
    if (mounted) setState(() => editorCommand = command);
  }

  /// The Settings "Test" button: open the plan from the repo root.
  Future<void> openTestFile(String file) async {
    try {
      await editors.open(file: '${repo.path}/$file');
    } on EditorException catch (error) {
      say(
        error.message,
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.openTestFile -> Editors.open',
          params: {'file': file},
        ),
        action: 'open',
      );
    }
  }

  /// "Open in editor" in the ignore pane.
  Future<void> openSelectedIgnore() async {
    final file = ignorePane.selected;
    if (file == null) {
      say('no ignore file selected');
      return;
    }
    try {
      await editors.open(file: '${repo.path}/${file.path}');
    } on EditorException catch (error) {
      say(
        error.message,
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.openSelectedIgnore -> Editors.open',
          params: {'file': file.path},
        ),
        action: 'open',
      );
    }
  }

  /// "New here": a `.gitignore` in the focused file's own folder.
  Future<void> newIgnoreHere() async {
    final row = changes.selected;
    if (row == null) {
      say('nothing selected');
      return;
    }
    final relative = row.folder.isEmpty ? '.gitignore' : '${row.folder}/.gitignore';
    try {
      await repo.createIgnoreFile('${repo.path}/$relative');
      await ignorePane.load();
      ignorePane.select(relative);
      await ignorePane.focusPath(row.path);
      await changes.load();
    } on Exception catch (error) {
      say(
        'could not create $relative',
        failure: ActionFailure.fromError(
          error,
          origin: 'Shell.newIgnoreHere -> Repo.createIgnoreFile',
          params: {'file': relative, 'cwd': repo.path},
        ),
        action: 'new ignore',
      );
    }
  }

  static const _altDigits = {
    Mode.changes: LogicalKeyboardKey.digit1,
    Mode.browse: LogicalKeyboardKey.digit2,
    Mode.settings: LogicalKeyboardKey.digit3,
    Mode.console: LogicalKeyboardKey.digit4,
    Mode.help: LogicalKeyboardKey.digit5,
  };

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: shellFocus,
      autofocus: true,
      onKeyEvent: onKey,
      child: Scaffold(
        body: Stack(
          children: [
            DebugBar(
              roles: appFocusRoles,
              child: Row(
                children: [
                  ModeRail(current: mode, onPick: show),
                  const VerticalDivider(width: 1),
                  Expanded(child: _body()),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 74,
              child: Center(child: NoticeBar(notices: notices)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() => IndexedStack(
        index: mode.index,
        children: [
          ChangesView(
            changes: changes,
            commitController: commitController,
            commitFocus: commitFocus,
            onIgnore: ignoreSelectedRow,
            onQuickIgnore: ignoreQuick,
            onTrack: trackSel,
            onUntrack: untrackSel,
            onOpen: openFocusedFile,
            onReload: reloadAll,
            filterController: filterController,
            filterFocus: filterFocus,
            ignoreState: ignorePane,
            onOpenIgnore: openSelectedIgnore,
            onNewIgnore: newIgnoreHere,
            onCommit: commitNow,
          ),
          BrowseView(browser: browser, current: repo.path, onOpen: openRepository),
          SettingsView(
            detect: editors.detect,
            chosenCommand: editorCommand ?? '',
            onChoose: chooseEditor,
            onTest: openTestFile,
          ),
          ConsoleView(log: console),
          const HelpView(),
        ],
      );
}

/// The mode rail: one stop in the Tab order, not one per mode.
class ModeRail extends StatelessWidget {
  const ModeRail({super.key, required this.current, required this.onPick});

  final Mode current;
  final ValueChanged<Mode> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final mode in Mode.values)
          _RailButton(
            mode: mode,
            active: mode == current,
            onTap: () => onPick(mode),
          ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.mode, required this.active, required this.onTap});

  final Mode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: mode.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            color: active ? scheme.secondaryContainer : null,
            child: Icon(
              mode.icon,
              size: 17,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
