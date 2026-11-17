/// The work behind the window: one open repository and everything tied to it,
/// the actions on it, and the one place they are reported.
///
/// The shell holds keys, focus and layout and calls the methods here; tests
/// drive this class with a `FakeRepo` and no widgets.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser.dart';
import 'changes.dart';
import 'console.dart';
import 'diagnostics.dart';
import 'editors.dart';
import 'failure.dart';
import 'git_repo.dart';
import 'ignore_files.dart';
import 'ignore_rules.dart';
import 'notices.dart';
import 'prefs.dart';
import 'status.dart';

/// Opens the repository at a path: `Repo.open` in the app, a fake in tests.
typedef RepoOpener = Future<GitRepo> Function(String path);

/// What the ignore dialog needs to ask: the row it is about and the files a
/// rule can go into.
class IgnoreQuestion {
  const IgnoreQuestion({required this.row, required this.targets});

  final StatusRow row;
  final List<IgnoreTarget> targets;
}

/// One open repository with its state, and every action the window offers.
///
/// API, in the order the window uses it:
///
/// - [start] once, after construction: first load, Browse scan, settings.
/// - [repo], [changes], [ignorePane], [browser], [console], [notices],
///   [editors], [prefs], [editorCommand]: what the views show. [changes] and
///   [ignorePane] are replaced by [open]; listen to this object to see that.
/// - Actions: [track], [untrack], [ignoreQuick], [ignoreQuestion] + [ignore],
///   [commit], [openFocused], [openSelectedIgnore], [openTestFile],
///   [newIgnoreHere], [reloadAll], [open], [chooseEditor]. None of them throws:
///   a failure is [say]-ed (notice + console row), a success [report]-ed
///   (console row only).
/// - [idle] completes when the background work is done; [dispose] stops it.
class Workspace extends ChangeNotifier {
  Workspace({
    required GitRepo repo,
    this.opener,
    Changes? changes,
    ConsoleLog? console,
    Notices? notices,
    Prefs? prefs,
    Editors? editors,
    RepoBrowser Function(String start, void Function(ScanReport) onReport)? browser,
    this.probeDelay = const Duration(milliseconds: 250),
  })  : _repo = repo,
        _ownsConsole = console == null,
        console = console ?? ConsoleLog(),
        notices = notices ?? Notices(),
        prefs = prefs ?? Prefs() {
    this.editors = editors ?? Editors(prefs: this.prefs);
    _changes = changes ?? Changes(repo);
    _ignorePane = IgnorePaneState(repo);
    this.browser = (browser ?? _realBrowser)(repo.path, logScan);
    _changes.addListener(_cursorMoved);
  }

  static RepoBrowser _realBrowser(String start, void Function(ScanReport) onReport) =>
      RepoBrowser(startDirectory: start, onReport: onReport);

  /// Null for a seeded workspace: Browse cannot switch it.
  final RepoOpener? opener;

  /// How long the cursor must rest before the ignore pane asks git.
  final Duration probeDelay;

  final ConsoleLog console;
  final bool _ownsConsole;
  final Notices notices;
  final Prefs prefs;
  late final Editors editors;
  late final RepoBrowser browser;

  GitRepo _repo;
  late Changes _changes;
  late IgnorePaneState _ignorePane;
  Timer? _probe;
  bool _disposed = false;

  /// The repository being shown; [open] replaces it.
  GitRepo get repo => _repo;
  Changes get changes => _changes;
  IgnorePaneState get ignorePane => _ignorePane;

  /// The saved editor command, once [start] has read the settings.
  String? editorCommand;

  Future<void>? _started;
  Future<void>? _prefsLoaded;

  /// The first load, the Browse scan (not awaited: [idle] has it) and the
  /// settings.
  Future<void> start() {
    unawaited(browser.scan());
    _prefsLoaded = _loadPrefs();
    return _started = reloadAll();
  }

  Future<void> _loadPrefs() async {
    await prefs.load();
    editorCommand = prefs.editorCommand;
    notifyListeners();
  }

  /// Completes when everything this object started in the background is done.
  Future<void> idle() async {
    await _started;
    await _prefsLoaded;
    await browser.idle();
    await _changes.idle();
    await _ignorePane.idle();
  }

  @override
  void dispose() {
    _disposed = true;
    _probe?.cancel();
    _changes.removeListener(_cursorMoved);
    _changes.dispose();
    _ignorePane.dispose();
    browser.dispose();
    notices.dispose();
    if (_ownsConsole) console.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // --- reporting -----------------------------------------------------------

  /// The one place a failure is reported: a notice that stays while the mouse
  /// is over it, and a console row with the full story.
  void say(String message, {ActionFailure? failure, String? action}) {
    if (_disposed) return;
    notices.show(message);
    console.add(
      failure ??
          ActionFailure(
            summary: message,
            detail: 'origin: Workspace.say\nmessage: $message',
            origin: 'Workspace.say',
          ),
      action: action,
    );
  }

  /// Every add, untrack and ignore lands here: a failure is said, a success
  /// gets a console row with the command line and the working directory.
  void report(String action, {String? problem}) {
    if (problem != null) {
      say(problem, failure: _changes.lastFailure, action: action);
      return;
    }
    final verb = switch (action) {
      'track' => 'tracked',
      'untrack' => 'stopped tracking',
      'ignore' => 'ignored',
      _ => action,
    };
    final changed = _changes.lastChanged;
    final files = changed == 1 ? '1 file' : '$changed files';
    console.add(
      ActionFailure.done(
        summary: '$verb $files',
        detail: [
          'origin: ${_changes.lastOrigin ?? '-'}',
          'changed: $changed',
          'cwd: ${_repo.path}',
          if (_changes.lastCommand != null) 'command: ${_changes.lastCommand}',
        ].join('\n'),
        origin: _changes.lastOrigin,
      ),
      action: action,
    );
  }

  /// Every scan writes one console row with its cost and its worst listings.
  void logScan(ScanReport report) {
    console.add(
      ActionFailure.done(summary: report.summary, detail: report.detail, origin: 'RepoBrowser.scan'),
      action: 'browse',
    );
  }

  // --- loading -------------------------------------------------------------

  /// Re-read everything an action can change: the status list, the ignore
  /// files and the highlight. `r`, F5 and Ctrl+R call this.
  Future<void> reloadAll() async {
    final clock = Stopwatch()..start();
    await _changes.load();
    await reloadIgnorePane();
    clock.stop();
    final rows = _changes.visible.length;
    final files = _ignorePane.files;
    console.add(
      ActionFailure.done(
        summary: 're-read ${_repo.path}  ${clock.elapsedMilliseconds} ms  '
            '$rows row(s), ${files.length} ignore file(s)',
        detail: [
          'origin: Workspace.reloadAll -> Changes.load -> Repo.status',
          'cwd: ${_repo.path}',
          'rows: $rows',
          'ignore files: ${files.map((file) => file.path).join(', ')}',
          'elapsed: ${clock.elapsedMilliseconds} ms',
        ].join('\n'),
        origin: 'Workspace.reloadAll',
      ),
      action: 'reload',
    );
  }

  /// The ignore files alone: after an ignore action they are what changed.
  Future<void> reloadIgnorePane() async {
    await _ignorePane.load();
    syncIgnoreFocus();
  }

  /// A move redraws the list; the ignore pane's `git check-ignore` runs only
  /// once the cursor has rested, so holding a key never waits on a subprocess.
  void _cursorMoved() {
    _probe?.cancel();
    _probe = Timer(probeDelay, syncIgnoreFocus);
  }

  /// Keep the ignore pane's highlight on the focused row.
  void syncIgnoreFocus() {
    final path = _changes.selected?.path;
    if (path == null || _disposed) return;
    unawaited(_ignorePane.focusPath(path)); // the pane's idle() has it
  }

  /// Browse: open another repository, which means new state for everything
  /// tied to the old one. Stays in Browse; the caller decides the mode.
  Future<void> open(String path) async {
    final opener = this.opener;
    if (opener == null) {
      say('this session was seeded with a repository; Browse cannot switch it', action: 'browse');
      return;
    }
    Diagnostics.enter('Browse: open $path');
    console.add(
      ActionFailure.done(
        summary: 'opening $path',
        detail: 'origin: Workspace.open\nclicked in the Browse list',
        origin: 'Workspace.open',
      ),
      action: 'browse',
    );
    try {
      final opened = await opener(path);
      final next = Changes(opened);
      await next.load();
      if (_disposed) {
        next.dispose();
        return;
      }
      _swap(opened, next);
      await reloadAll();
      browser.directory = opened.path;
      unawaited(browser.scan());
      console.add(
        ActionFailure.done(
          summary: 'opened ${opened.path}',
          detail: 'origin: Workspace.open -> RepoOpener\ncwd: ${opened.path}'
              '\nrows: ${_changes.visible.length}',
          origin: 'Workspace.open',
        ),
        action: 'browse',
      );
    } catch (error) {
      // `Object`, not `Exception`: a failure here can be an Error (see
      // Repo.open), and it must become a notice, not a zone crash.
      say(
        'cannot open $path',
        failure: ActionFailure.fromError(error, origin: 'Workspace.open -> RepoOpener', params: {'path': path}),
        action: 'browse',
      );
      browser.drop(path);
    } finally {
      Diagnostics.leave();
    }
  }

  void _swap(GitRepo opened, Changes next) {
    _probe?.cancel();
    _changes.removeListener(_cursorMoved);
    _changes.dispose();
    _ignorePane.dispose();
    _repo = opened;
    _changes = next..addListener(_cursorMoved);
    _ignorePane = IgnorePaneState(opened);
    notifyListeners();
  }

  // --- actions -------------------------------------------------------------

  /// `space` / `a`: stage the highlighted rows, at once.
  Future<void> track() => _act('track', _changes.trackSelected);

  /// `u`: stop tracking the highlighted rows, at once.
  Future<void> untrack() => _act('untrack', _changes.untrackSelected);

  /// `i`: ignore the highlighted rows with their literal path in the root
  /// `.gitignore`. The rows leaving is the feedback; only a refusal speaks.
  Future<void> ignoreQuick() => _act('ignore', () async {
        final problem = await _changes.ignoreQuick();
        await reloadIgnorePane();
        return problem;
      });

  /// Shift+I, step one: what the dialog should offer, or null when there is
  /// nothing to ask (and that has been said).
  Future<IgnoreQuestion?> ignoreQuestion() async {
    final row = _changes.selected;
    if (row == null) {
      say('nothing selected to ignore', action: 'ignore');
      return null;
    }
    try {
      final targets = await _changes.ignoreTargets();
      if (targets.isEmpty) {
        say('no ignore file to write to for ${row.path}', action: 'ignore');
        return null;
      }
      return IgnoreQuestion(row: row, targets: targets);
    } on Exception catch (error) {
      say(
        'ignore failed',
        failure: ActionFailure.fromError(error,
            origin: 'Workspace.ignoreQuestion -> Changes.ignoreTargets', params: {'row': row.path}),
        action: 'ignore',
      );
      return null;
    }
  }

  /// Shift+I, step two: write what the dialog chose.
  Future<void> ignore({
    required IgnoreScope scope,
    required IgnoreTarget target,
    bool stopTracking = false,
  }) =>
      _act('ignore', () async {
        final problem = await _changes.ignoreSelected(
          scope: scope,
          target: target,
          stopTracking: stopTracking,
        );
        await reloadIgnorePane();
        return problem;
      });

  /// Run one row action and report it; an exception becomes a notice.
  Future<void> _act(String action, Future<String?> Function() run) async {
    Diagnostics.enter('Changes: $action (${_changes.selectionCount} selected)');
    try {
      final problem = await run();
      report(action, problem: problem);
    } on Exception catch (error) {
      say(
        '$action failed',
        failure: ActionFailure.fromError(
          error,
          origin: 'Workspace.$action',
          params: {'selected': _changes.selectionCount},
        ),
        action: action,
      );
    } finally {
      Diagnostics.leave();
    }
  }

  /// The Commit button: true when the commit was made.
  Future<bool> commit(String summary) async {
    Diagnostics.enter('Changes: commit');
    try {
      final ok = await _changes.commit(summary);
      if (ok) {
        report('commit');
      } else {
        say(_changes.error ?? 'commit failed', failure: _changes.lastFailure, action: 'commit');
      }
      return ok;
    } finally {
      Diagnostics.leave();
    }
  }

  /// `e`: open the focused file in the chosen editor.
  Future<void> openFocused() async {
    final row = _changes.selected;
    if (row == null) {
      say('nothing selected to open', action: 'open');
      return;
    }
    if (row.path.endsWith('/')) {
      say('${row.path} is a folder', action: 'open');
      return;
    }
    await _openInEditor(row.path, origin: 'Workspace.openFocused');
  }

  /// `E` and the ignore pane's "Open in editor".
  Future<void> openSelectedIgnore() async {
    final file = _ignorePane.selected;
    if (file == null) {
      say('no ignore file selected', action: 'open');
      return;
    }
    await _openInEditor(file.path, origin: 'Workspace.openSelectedIgnore');
  }

  /// The Settings "Test" button: open [file] from the repository root.
  Future<void> openTestFile(String file) => _openInEditor(file, origin: 'Workspace.openTestFile');

  Future<void> _openInEditor(String relative, {required String origin}) async {
    try {
      await editors.open(file: '${_repo.path}/$relative');
    } on EditorException catch (error) {
      say(
        error.message,
        failure: ActionFailure.fromError(error, origin: '$origin -> Editors.open', params: {'file': relative}),
        action: 'open',
      );
    }
  }

  /// "New here": a `.gitignore` in the focused file's own folder.
  Future<void> newIgnoreHere() async {
    final row = _changes.selected;
    if (row == null) {
      say('nothing selected', action: 'new ignore');
      return;
    }
    final relative = row.folder.isEmpty ? '.gitignore' : '${row.folder}/.gitignore';
    try {
      await _repo.createIgnoreFile('${_repo.path}/$relative');
      await _ignorePane.load();
      _ignorePane.select(relative);
      await _ignorePane.focusPath(row.path);
      await _changes.load();
    } on Exception catch (error) {
      say(
        'could not create $relative',
        failure: ActionFailure.fromError(
          error,
          origin: 'Workspace.newIgnoreHere -> GitRepo.createIgnoreFile',
          params: {'file': relative, 'cwd': _repo.path},
        ),
        action: 'new ignore',
      );
    }
  }

  /// Settings: save the editor command (null clears it).
  Future<void> chooseEditor(String? command) async {
    await prefs.setEditorCommand(command);
    editorCommand = command;
    notifyListeners();
  }
}
