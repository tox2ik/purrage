import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'failure.dart';
import 'git_repo.dart';
import 'ignore_rules.dart';
import 'status.dart';

/// The state of the Changes mode: what git says, which rows are selected, the
/// cursor, the filter, and the actions.
///
/// A selection follows the usual desktop rules: a plain click picks one row, Ctrl
/// toggles a row, Shift takes the range from the anchor. Every action takes the
/// selection, or the cursor row when nothing is selected.
///
/// Everything the UI needs to decide is here, so tests drive this class without
/// widgets.
class Changes extends ChangeNotifier {
  Changes(this.repo);

  final GitRepo repo;

  List<StatusRow> _rows = const [];
  List<StatusRow> _visible = const [];
  final Set<String> _selection = {};
  int? _anchor;
  String _filter = '';
  int _index = 0;
  bool _busy = false;
  String? _error;

  List<StatusRow> get rows => _rows;

  /// The rows the list shows: [rows] narrowed by [filter].
  List<StatusRow> get visible => _visible;

  String get filter => _filter;

  int get index => _index;
  bool get busy => _busy;
  String? get error => _error;

  /// The row under the cursor.
  StatusRow? get selected => _visible.isEmpty ? null : _visible[_index];

  /// The rows the actions work on: exactly the highlighted ones. A plain move
  /// highlights the row it lands on, so there is always a target unless the user
  /// turned everything off with Ctrl+Enter.
  List<StatusRow> get actionRows => selectedRows;

  /// The git steps of the actions, one at a time: each starts when the one
  /// before it has ended. The screen does not wait for the queue; only git
  /// does.
  Future<void> _queue = Future<void>.value();

  /// Actions whose git step has not ended yet. While one is pending, a
  /// finished one does not re-read `git status`: the answer would not have the
  /// pending change in it yet, and the row would flicker back.
  int _pending = 0;

  /// Run [step] after every git step queued before it.
  Future<ActionResult> _enqueue(Future<ActionResult> Function() step) {
    _pending++;
    final run = _queue.then((_) => step()).whenComplete(() => _pending--);
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// The truth from git once the last queued action has ended.
  Future<void> _settle() async {
    if (_pending <= 1) await refresh();
  }

  /// Rows whose folder is a repository of its own, and the ones already asked
  /// about, so a reload does not stat the same path again.
  final Set<String> _nested = {};
  final Set<String> _scanned = {};

  /// True when the row's folder holds a `.git` of its own.
  bool isNested(StatusRow row) => _nested.contains(_dirKey(row.path));

  static String _dirKey(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// Ask once per path whether it is an embedded repository, and redraw when a
  /// new one is found.
  ///
  /// Called only from `load()`: startup and an explicit reload (`r`, `F5`,
  /// `Ctrl+R`). Actions must not pay for it — they redraw the list, and this stat
  /// per directory row is what made scrolling stutter on Windows.
  Future<void> _scanNested(List<StatusRow> rows) async {
    final links = await repo.gitlinks();
    if (_disposed) return;
    for (final link in links) {
      _nested.add(link);
    }

    // Only a directory row can hold a `.git`: those are the ones git prints with
    // a trailing slash. Files are never stat-ed.
    var asked = 0;
    for (final row in rows) {
      if (!row.path.endsWith('/')) continue;
      final key = _dirKey(row.path);
      if (key.isEmpty || !_scanned.add(key)) continue;
      if (links.contains(key)) {
        _nested.add(key);
        continue;
      }
      final nested = await repo.isNestedRepository(key);
      if (_disposed) return;
      if (nested) _nested.add(key);
      // Hand the frame back every so often, so a hundred stats cannot hold the
      // event loop while the user scrolls.
      if (++asked % 20 == 0) await Future<void>.delayed(Duration.zero);
    }
    notifyListeners();
  }

  /// The nested-repository probe that `load()` started and nobody awaits, kept
  /// so [idle] and [dispose] can find it.
  Future<void>? _nestedScan;
  bool _disposed = false;

  /// Completes when every background job this object started is done. Tests
  /// await it before their temp repository is deleted: Windows will not delete
  /// a folder that is a live git process's working directory.
  Future<void> idle() async {
    while (_nestedScan != null) {
      final running = _nestedScan!;
      await running;
      if (identical(_nestedScan, running)) _nestedScan = null;
    }
  }

  /// No further probe starts, and a running one stops at its next step without
  /// redrawing.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// An action that ends after its owner was disposed (Browse switched the
  /// repository) has nobody to redraw.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  List<StatusRow> get selectedRows => [
        for (final row in _visible)
          if (isSelected(row)) row,
      ];

  int get selectionCount => selectedRows.length;

  bool isSelected(StatusRow row) => _selection.contains(_key(row));

  /// Rows of one section, in display order.
  List<StatusRow> section(Section section) =>
      _visible.where((row) => row.section == section).toList();

  int get stagedCount => _rows.where((row) => row.section == Section.staged).length;

  bool get canCommit => stagedCount > 0 && !_busy;

  static String _key(StatusRow row) => '${row.section.index}\u0000${row.path}';

  /// Reload from git, keeping the cursor on the same path when it still exists.
  ///
  /// The nested-repository probe runs after the list is on screen and is not
  /// awaited: the rows must not wait on a hundred stats. [idle] waits for it.
  Future<void> load() async {
    _busy = true;
    notifyListeners();
    final keepPath = selected?.path;
    try {
      final rows = await repo.status();
      _rows = [...rows]..sort(_compare);
      _applyFilter();
      _pruneSelection();
      _index = _indexAfterReload(keepPath);
      _selectCursorIfEmpty();
      _error = null;
    } on GitException catch (error) {
      _error = error.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (!_disposed) _nestedScan = _scanNested(_rows);
  }

  /// A reload can drop rows; their keys must not linger in the selection.
  void _pruneSelection() {
    final keys = {for (final row in _visible) _key(row)};
    _selection.retainWhere(keys.contains);
  }

  void _selectCursorIfEmpty() {
    if (_selection.isNotEmpty || _visible.isEmpty) return;
    _selection.add(_key(_visible[_index]));
  }

  int _indexAfterReload(String? keepPath) {
    if (_visible.isEmpty) return 0;
    if (keepPath == null) return _index.clamp(0, _visible.length - 1);
    final found = _visible.indexWhere((row) => row.path == keepPath);
    if (found >= 0) return found;
    return _index.clamp(0, _visible.length - 1);
  }

  static int _compare(StatusRow a, StatusRow b) {
    final bySection = a.section.index.compareTo(b.section.index);
    if (bySection != 0) return bySection;
    // The two columns decide the order: folder first, then base name, both
    // case-insensitive, matching what the eye scans.
    final byFolder = a.folder.toLowerCase().compareTo(b.folder.toLowerCase());
    if (byFolder != 0) return byFolder;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Narrow the list; the cursor goes to the first match and is the selection.
  Future<void> setFilter(String query) async {
    if (query == _filter) return;
    _filter = query;
    _applyFilter();
    _index = 0;
    _selection.clear();
    _anchor = null;
    _selectCursorIfEmpty();
    notifyListeners();
  }

  void _applyFilter() {
    _visible = filterRows(_rows, _filter);
  }

  /// Move the cursor by [delta] rows; a plain move makes that row the selection.
  Future<void> move(int delta) async {
    if (_visible.isEmpty) return;
    final next = (_index + delta).clamp(0, _visible.length - 1);
    if (next == _index) return;
    _index = next;
    _selection
      ..clear()
      ..add(_key(_visible[next]));
    _anchor = next;
    notifyListeners();
  }

  /// Shift+Up / Shift+Down: move the cursor one row and take the range from the
  /// anchor with it, so the earlier rows stay highlighted.
  Future<void> extendSelection(int delta) async {
    if (_visible.isEmpty) return;
    final next = (_index + delta).clamp(0, _visible.length - 1);
    if (next == _index) return;
    final from = _anchor ?? _index;
    _index = next;
    final low = from < next ? from : next;
    final high = from < next ? next : from;
    _selection.clear();
    for (var i = low; i <= high; i++) {
      _selection.add(_key(_visible[i]));
    }
    _anchor = from;
    notifyListeners();
  }

  /// Ctrl+Enter: turn the cursor row's highlight on or off, leaving the rest of
  /// the selection alone.
  Future<void> toggleFocused() async {
    final row = selected;
    if (row == null) return;
    final key = _key(row);
    if (!_selection.remove(key)) _selection.add(key);
    _anchor = _index;
    notifyListeners();
  }

  /// A click in the list. [ctrl] toggles one row, [shift] takes the range from
  /// the anchor, a plain click selects just that row.
  Future<void> click(int index, {bool ctrl = false, bool shift = false}) async {
    if (_visible.isEmpty) return;
    final next = index.clamp(0, _visible.length - 1);
    final row = _visible[next];
    if (shift) {
      final from = _anchor ?? _index;
      final low = from < next ? from : next;
      final high = from < next ? next : from;
      _selection.clear();
      for (var i = low; i <= high; i++) {
        _selection.add(_key(_visible[i]));
      }
    } else if (ctrl) {
      final key = _key(row);
      if (!_selection.remove(key)) _selection.add(key);
      _anchor = next;
    } else {
      _selection
        ..clear()
        ..add(_key(row));
      _anchor = next;
    }
    _index = next;
    if (_selection.isEmpty) _selection.add(_key(row));
    notifyListeners();
  }

  /// A row's own action button was clicked: act on that row, unless it is part
  /// of the selection, in which case the whole selection is the target.
  void target(int index) {
    if (index < 0 || index >= _visible.length) return;
    if (!isSelected(_visible[index])) click(index);
  }

  /// Select every visible row.
  Future<void> selectAll() async {
    _selection
      ..clear()
      ..addAll(_visible.map(_key));
    _anchor = 0;
    notifyListeners();
  }

  /// Stage the highlighted rows, at once, then let git confirm.
  ///
  /// The rows move to Staged before `git add` runs; on a failure exactly that
  /// move is undone (other actions' rows stay as they are) and the result says
  /// why. That is the whole point of the app feeling instant: the click does
  /// not wait on a subprocess.
  Future<ActionResult> trackSelected() async {
    const origin = 'Changes.trackSelected -> Repo.track -> git add';
    final rows = actionRows;
    if (rows.isEmpty) return ActionResult.refused('track', 'nothing selected', origin);
    final usable = rows.where((row) => !row.isConflict).toList();
    if (usable.isEmpty) {
      return ActionResult.refused('track', 'a conflict offers only ignore and open', origin);
    }

    // A changed row joins its staged twin; a staged row stays where it is.
    final moving = usable.where((row) => !row.isStaged).toList();
    final stagedPaths = {for (final row in _rows) if (row.isStaged) row.path};
    final change = _RowChange(
      removed: moving,
      added: [
        for (final row in moving)
          if (!stagedPaths.contains(row.path))
            StatusRow(section: Section.staged, kind: row.kind, path: row.path, code: row.code),
      ],
    );
    _apply(change);

    final pathList = usable.map((row) => row.path).toList();
    final command = 'git add -- ${pathList.take(8).join(' ')}'
        '${pathList.length > 8 ? ' ...(${pathList.length} paths)' : ''}';
    return _enqueue(() async {
      try {
        await repo.track(pathList);
      } on Exception catch (error) {
        _undo(change);
        return ActionResult.failed(
          'track',
          ActionFailure.fromError(
            error,
            origin: origin,
            summary: 'could not stage ${pathList.length} file(s)',
            params: {'selected': rows.length, 'cwd': repo.path, 'first': pathList.first},
            command: command,
          ),
        );
      }
      await _settle();
      return ActionResult.done('track', origin: origin, command: command, changed: pathList.length);
    });
  }

  /// Stop tracking the highlighted rows, at once, then let git confirm.
  Future<ActionResult> untrackSelected() async {
    const origin = 'Changes.untrackSelected -> Repo.untrack -> git rm --cached';
    final rows = actionRows
        .where((row) => !row.isConflict && row.section != Section.untracked)
        .toList();
    if (rows.isEmpty) return ActionResult.refused('untrack', 'nothing to stop tracking', origin);

    final paths = rows.map((row) => row.path).toSet();
    final change = _RowChange(removed: [for (final row in _rows) if (paths.contains(row.path)) row]);
    _apply(change);

    final planned = 'git rm --cached -- ${rows.take(8).map((row) => row.path).join(' ')}';
    return _enqueue(() async {
      try {
        for (final row in rows) {
          await repo.untrack(row.path);
        }
      } on Exception catch (error) {
        _undo(change);
        return ActionResult.failed(
          'untrack',
          ActionFailure.fromError(
            error,
            origin: origin,
            summary: 'could not stop tracking ${rows.length} file(s)',
            params: {'rows': rows.length, 'cwd': repo.path},
            command: planned,
          ),
        );
      }
      // A gitlink needed `-f`; report the command that actually ran. Only this
      // action runs git now, so the repository's last command is its own.
      final command = repo.lastCommand ?? planned;
      await _settle();
      return ActionResult.done('untrack', origin: origin, command: command, changed: rows.length);
    });
  }

  /// Commit the index with one summary line, after every queued action.
  Future<ActionResult> commit(String summary) async {
    const origin = 'Changes.commit -> Repo.commit -> git commit';
    final message = summary.trim();
    if (message.isEmpty) return ActionResult.refused('commit', 'the summary is empty', origin);
    if (!canCommit) return ActionResult.refused('commit', 'nothing is staged', origin);
    final changed = stagedCount;
    _busy = true;
    _error = null;
    notifyListeners();
    return _enqueue(() async {
      try {
        await repo.commit(message);
      } on Exception catch (error) {
        _error = error is GitException ? error.message : error.toString();
        return ActionResult.failed(
          'commit',
          ActionFailure.fromError(
            error,
            origin: origin,
            params: {'cwd': repo.path},
            command: 'git commit -m <summary>',
          ),
        );
      } finally {
        _busy = false;
        notifyListeners();
      }
      await load();
      return ActionResult.done(
        'commit',
        origin: origin,
        command: 'git commit -m ${message.replaceAll('\n', ' ')}',
        changed: changed,
      );
    });
  }

  /// Put [change] on screen.
  void _apply(_RowChange change) => _setRows(change.applyTo(_rows));

  /// Take [change] back from the rows as they are now, leaving every other
  /// action's change in place.
  void _undo(_RowChange change) => _setRows(change.undoFrom(_rows));

  /// The ignore files to offer, narrowest first, for the cursor row.
  Future<List<IgnoreTarget>> ignoreTargets() async {
    final row = selected;
    if (row == null) return const [];
    final gitignores = await repo.gitignoreFiles();
    return IgnoreRules.targets(
      repoPath: repo.path,
      gitignoreFiles: gitignores,
      localExclude: await repo.localExcludePath(),
      globalIgnore: await repo.globalIgnorePath(),
      path: row.path,
    );
  }

  /// The rule [scope] would write into [target], for the dialog preview.
  static String? previewPattern({
    required IgnoreScope scope,
    required IgnoreTarget target,
    required String path,
  }) =>
      IgnoreRules.pattern(scope: scope, targetDir: target.dir, path: path);

  /// The rules the dialog is about to write, one line per row it will act on.
  List<String> ignorePreviews({
    required IgnoreScope scope,
    required IgnoreTarget target,
  }) {
    final lines = <String>[];
    for (final row in actionRows) {
      final pattern = IgnoreRules.pattern(
        scope: scope,
        targetDir: _targetFor(row, target).dir,
        path: row.path,
      );
      lines.add(pattern ?? '${row.name}: no rule for this scope');
    }
    return lines;
  }

  /// A rule for a folder file follows the row's own folder when several rows are
  /// being ignored together.
  IgnoreTarget _targetFor(StatusRow row, IgnoreTarget target) {
    if (target.kind != IgnoreTargetKind.folderGitignore || row.folder.isEmpty) {
      return target;
    }
    final root = repo.path.replaceAll(r'\', '/');
    return IgnoreTarget(
      kind: target.kind,
      label: row.folder,
      path: '$root/${row.folder}/.gitignore',
      dir: row.folder,
      exists: false,
    );
  }

  /// The root `.gitignore`, for the one-key ignore.
  IgnoreTarget get rootTarget => IgnoreTarget(
        kind: IgnoreTargetKind.rootGitignore,
        label: 'root',
        path: '${repo.path.replaceAll(r'\', '/')}/.gitignore',
        dir: '',
        exists: true,
      );

  /// One key, no questions: ignore every row the action covers with its literal
  /// path written to the root `.gitignore` (`/dir/file.ext`).
  Future<ActionResult> ignoreQuick() =>
      ignoreSelected(scope: IgnoreScope.file, target: rootTarget);

  /// Write an ignore rule for every highlighted row, removing them at once.
  ///
  /// The result is a success when every rule was written, or a failure whose
  /// summary names what was skipped and why. Rows whose rule failed come back.
  Future<ActionResult> ignoreSelected({
    required IgnoreScope scope,
    required IgnoreTarget target,
    bool stopTracking = false,
  }) async {
    const origin = 'Changes.ignoreSelected -> IgnoreRules.pattern -> Repo.appendIgnoreLine';
    final rows = actionRows;
    if (rows.isEmpty) return ActionResult.refused('ignore', 'nothing selected', origin);
    final skipped = <String>[];
    final plans = <_IgnorePlan>[];
    for (final row in rows) {
      final rowTarget = _targetFor(row, target);
      final pattern = IgnoreRules.pattern(
        scope: scope,
        targetDir: rowTarget.dir,
        path: row.path,
      );
      if (pattern == null) {
        skipped.add('${row.name}: no rule for this scope');
        continue;
      }
      final existing = await repo.checkIgnore(row.path);
      if (existing != null) {
        final where = '${_shortSource(existing.source)}:${existing.line}';
        skipped.add('${row.path}: `${existing.pattern}` in $where');
        continue;
      }
      plans.add(_IgnorePlan(row: row, target: rowTarget, pattern: pattern));
    }

    Map<String, Object?> params(int written) => {
          'scope': scope.name,
          'target': _shortSource(target.path),
          'stopTracking': stopTracking,
          'rows': rows.length,
          'written': written,
        };

    if (plans.isEmpty) {
      if (skipped.isEmpty) return ActionResult.refused('ignore', 'nothing selected', origin);
      // Every row was refused: keep the reason, the origin and the parameters so
      // the console says where this came from instead of "Workspace.say".
      return ActionResult.failed(
        'ignore',
        ActionFailure.fromSkips(
          origin: 'Changes.ignoreSelected -> Repo.checkIgnore',
          summary: skipped.take(3).join('; '),
          skipped: skipped,
          params: params(0),
        ),
      );
    }

    // They leave the list now; git gets the files written right after.
    final paths = plans.map((plan) => plan.row.path).toSet();
    _apply(_RowChange(removed: [for (final row in _rows) if (paths.contains(row.path)) row]));

    final command = plans
            .map((plan) => '${_shortSource(plan.target.path)} += ${plan.pattern}')
            .take(8)
            .join('\n') +
        (plans.length > 8 ? '\n...(${plans.length} rules)' : '');
    return _enqueue(() async {
      var added = 0;
      for (final plan in plans) {
        final problem = await _writeRule(plan, stopTracking: stopTracking);
        if (problem == null) {
          added++;
          continue;
        }
        skipped.add(problem);
        // This row's rule was not written: it comes back, and only it.
        _undo(_RowChange(removed: [plan.row]));
      }
      await _settle();
      if (skipped.isEmpty) {
        return ActionResult.done('ignore', origin: origin, command: command, changed: added);
      }
      final head = skipped.take(3).join('; ');
      final more = skipped.length > 3 ? ' (+${skipped.length - 3} more)' : '';
      return ActionResult.failed(
        'ignore',
        ActionFailure.fromSkips(
          origin: origin,
          summary: 'ignored $added, skipped ${skipped.length}: $head$more',
          skipped: skipped,
          params: params(added),
        ),
        command: command,
        changed: added,
      );
    });
  }

  /// Write one planned rule; null when it was written, else why not.
  Future<String?> _writeRule(_IgnorePlan plan, {required bool stopTracking}) async {
    try {
      final appended = await repo.appendIgnoreLine(plan.target.path, plan.pattern);
      if (appended == IgnoreAppend.duplicate) {
        return '${plan.row.path}: `${plan.pattern}` already there';
      }
      if (stopTracking) await repo.untrack(plan.row.path);
      return null;
    } on GitException catch (error) {
      return '${plan.row.path}: ${error.message}';
    } on FileSystemException catch (error) {
      return '${plan.row.path}: cannot write ${plan.target.path} (${_osText(error)})';
    }
  }

  /// Replace the list with [rows], keeping the filter, the cursor and the
  /// selection coherent, and redraw.
  void _setRows(List<StatusRow> rows) {
    _rows = [...rows]..sort(_compare);
    _applyFilter();
    _pruneSelection();
    _index = _visible.isEmpty ? 0 : _index.clamp(0, _visible.length - 1);
    _selectCursorIfEmpty();
    notifyListeners();
  }

  /// Ask git for the truth after an optimistic change, without the busy state
  /// that makes the UI feel stuck. Nothing is redrawn when nothing moved.
  Future<void> refresh() async {
    try {
      final rows = await repo.status();
      final sorted = [...rows]..sort(_compare);
      if (_sameRows(sorted, _rows)) return;
      _setRows(sorted);
      _error = null;
    } on GitException catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  static bool _sameRows(List<StatusRow> a, List<StatusRow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].section != b[i].section || a[i].path != b[i].path || a[i].code != b[i].code) {
        return false;
      }
    }
    return true;
  }

  String _shortSource(String path) {
    final repoPath = repo.path.replaceAll(r'\', '/');
    final clean = path.replaceAll(r'\', '/');
    return clean.startsWith('$repoPath/') ? clean.substring(repoPath.length + 1) : clean;
  }

  /// Windows puts the useful part in `osError` ("Access is denied"), and the
  /// bare exception only says errno 5.
  static String _osText(FileSystemException error) {
    final code = error.osError?.errorCode;
    final detail = error.osError?.message ?? error.message;
    return code == null ? detail : '$detail, error $code';
  }

}

/// One rule the ignore action is about to write.
class _IgnorePlan {
  const _IgnorePlan({required this.row, required this.target, required this.pattern});

  final StatusRow row;
  final IgnoreTarget target;
  final String pattern;
}

/// One action's optimistic change to the list: the rows it took out and the
/// rows it put in. Undoing it touches those rows only, so a failure cannot
/// undo another action's change.
class _RowChange {
  const _RowChange({this.removed = const [], this.added = const []});

  final List<StatusRow> removed;
  final List<StatusRow> added;

  static String _key(StatusRow row) => '${row.section.index}\u0000${row.path}';

  List<StatusRow> applyTo(List<StatusRow> rows) {
    final gone = {for (final row in removed) _key(row)};
    return [
      for (final row in rows)
        if (!gone.contains(_key(row))) row,
      ...added,
    ];
  }

  List<StatusRow> undoFrom(List<StatusRow> rows) {
    final mine = {for (final row in added) _key(row)};
    final kept = [
      for (final row in rows)
        if (!mine.contains(_key(row))) row,
    ];
    final present = {for (final row in kept) _key(row)};
    return [
      ...kept,
      for (final row in removed)
        if (!present.contains(_key(row))) row,
    ];
  }
}

/// What one action did, returned by that action alone: the console line and
/// the notice are built from it, never from fields a later action may have
/// overwritten.
class ActionResult {
  const ActionResult._({
    required this.action,
    this.failure,
    this.origin,
    this.command,
    this.changed = 0,
  });

  /// It worked: [changed] rows, by [command].
  const ActionResult.done(
    String action, {
    required String origin,
    String? command,
    required int changed,
  }) : this._(action: action, origin: origin, command: command, changed: changed);

  /// It failed, or was refused, with the full story in [failure].
  ActionResult.failed(String action, ActionFailure failure, {String? command, int changed = 0})
      : this._(
          action: action,
          failure: failure,
          origin: failure.origin,
          command: command,
          changed: changed,
        );

  /// Nothing to do, said in one sentence: "nothing selected".
  ActionResult.refused(String action, String why, String origin)
      : this._(
          action: action,
          origin: origin,
          failure: ActionFailure(
            summary: why,
            detail: 'origin: $origin\nrefused: $why',
            origin: origin,
          ),
        );

  /// `track`, `untrack`, `ignore`, `commit`.
  final String action;

  /// Null when it worked.
  final ActionFailure? failure;
  final String? origin;
  final String? command;
  final int changed;

  bool get ok => failure == null;

  /// The sentence the notice shows, or null for a success.
  String? get problem => failure?.summary;
}
