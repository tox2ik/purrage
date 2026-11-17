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

  /// What the last action did, for the one message the UI shows.
  ActionReport? lastReport;

  /// The last failure, with its origin, code and detail, for the Console mode.
  ActionFailure? lastFailure;

  /// How the last action ran, for the console's success line.
  String? lastCommand;
  String? lastOrigin;
  int lastChanged = 0;

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
    return bySection != 0 ? bySection : a.path.compareTo(b.path);
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
  /// The rows move to Staged before `git add` runs; on a failure the previous
  /// list comes back and the message says why. That is the whole point of the
  /// app feeling instant: the click does not wait on a subprocess.
  Future<String?> trackSelected() async {
    final rows = actionRows;
    if (rows.isEmpty) return 'nothing selected';
    final usable = rows.where((row) => !row.isConflict).toList();
    if (usable.isEmpty) return 'a conflict offers only ignore and open';

    final before = _rows;
    final paths = usable.map((row) => row.path).toSet();
    final next = [
      for (final row in _rows)
        if (!paths.contains(row.path) || row.section == Section.staged) row,
      for (final row in usable)
        if (row.section != Section.staged)
          StatusRow(section: Section.staged, kind: row.kind, path: row.path, code: row.code),
    ];
    _setRows(next);

    final pathList = usable.map((row) => row.path).toList();
    lastOrigin = 'Changes.trackSelected -> Repo.track -> git add';
    lastCommand = 'git add -- ${pathList.take(8).join(' ')}'
        '${pathList.length > 8 ? ' ...(${pathList.length} paths)' : ''}';
    lastChanged = pathList.length;
    try {
      await repo.track(pathList);
    } on Exception catch (error) {
      _setRows(before);
      lastFailure = ActionFailure.fromError(
        error,
        origin: 'Changes.trackSelected -> Repo.track -> git add',
        summary: 'could not stage ${pathList.length} file(s)',
        params: {'selected': rows.length, 'cwd': repo.path, 'first': pathList.first},
        command: 'git add -- ${pathList.take(5).join(' ')}',
      );
      return lastFailure!.summary;
    }
    await refresh();
    return null;
  }

  /// Stop tracking the highlighted rows, at once, then let git confirm.
  Future<String?> untrackSelected() async {
    final rows = actionRows.where((row) => !row.isConflict && row.section != Section.untracked);
    if (rows.isEmpty) return 'nothing to stop tracking';

    final before = _rows;
    final paths = rows.map((row) => row.path).toSet();
    _setRows([for (final row in _rows) if (!paths.contains(row.path)) row]);

    lastOrigin = 'Changes.untrackSelected -> Repo.untrack -> git rm --cached';
    lastCommand = 'git rm --cached -- ${rows.take(8).map((row) => row.path).join(' ')}';
    lastChanged = rows.length;
    try {
      for (final row in rows) {
        await repo.untrack(row.path);
      }
    } on Exception catch (error) {
      _setRows(before);
      lastFailure = ActionFailure.fromError(
        error,
        origin: 'Changes.untrackSelected -> Repo.untrack -> git rm --cached',
        summary: 'could not stop tracking ${rows.length} file(s)',
        params: {'rows': rows.length, 'cwd': repo.path},
        command: 'git rm --cached -- ${rows.take(5).map((row) => row.path).join(' ')}',
      );
      return lastFailure!.summary;
    }
    await refresh();
    return null;
  }

  /// Commit the index with one summary line.
  Future<bool> commit(String summary) async {
    final message = summary.trim();
    if (message.isEmpty || !canCommit) return false;
    lastOrigin = 'Changes.commit -> Repo.commit -> git commit';
    lastCommand = 'git commit -m ${message.replaceAll('\n', ' ')}';
    lastChanged = stagedCount;
    await _run(
      () => repo.commit(message),
      origin: 'Changes.commit -> Repo.commit -> git commit',
      command: 'git commit -m <summary>',
    );
    return _error == null;
  }

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
  Future<String?> ignoreQuick() =>
      ignoreSelected(scope: IgnoreScope.file, target: rootTarget);

  /// Write an ignore rule for every highlighted row, removing them at once.
  ///
  /// Returns null when every rule was written, or a sentence naming what was
  /// skipped and why. Rows whose rule failed come back with the next refresh.
  Future<String?> ignoreSelected({
    required IgnoreScope scope,
    required IgnoreTarget target,
    bool stopTracking = false,
  }) async {
    final rows = actionRows;
    if (rows.isEmpty) return 'nothing selected';
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

    if (plans.isEmpty) {
      return skipped.isEmpty ? 'nothing selected' : skipped.take(3).join('; ');
    }

    // They leave the list now; git gets the files written right after.
    final paths = plans.map((plan) => plan.row.path).toSet();
    _setRows([
      for (final row in _rows)
        if (!paths.contains(row.path)) row,
    ]);

    var added = 0;
    for (final plan in plans) {
      try {
        final appended = await repo.appendIgnoreLine(plan.target.path, plan.pattern);
        if (appended == IgnoreAppend.duplicate) {
          skipped.add('${plan.row.path}: `${plan.pattern}` already there');
          continue;
        }
        if (stopTracking) await repo.untrack(plan.row.path);
        added++;
      } on GitException catch (error) {
        skipped.add('${plan.row.path}: ${error.message}');
      } on FileSystemException catch (error) {
        skipped.add('${plan.row.path}: cannot write ${plan.target.path} '
            '(${_osText(error)})');
      }
    }
    await refresh();
    lastReport = ActionReport(done: added, skipped: skipped, note: _shortSource(target.path));
    lastChanged = added;
    lastOrigin = 'Changes.ignoreSelected -> IgnoreRules.pattern -> Repo.appendIgnoreLine';
    lastCommand = plans
        .map((plan) => '${_shortSource(plan.target.path)} += ${plan.pattern}')
        .take(8)
        .join('\n') +
        (plans.length > 8 ? '\n...(${plans.length} rules)' : '');
    if (skipped.isEmpty) return null;
    final head = skipped.take(3).join('; ');
    final more = skipped.length > 3 ? ' (+${skipped.length - 3} more)' : '';
    final summary = 'ignored $added, skipped ${skipped.length}: $head$more';
    lastFailure = ActionFailure.fromSkips(
      origin: 'Changes.ignoreSelected -> IgnoreRules.pattern -> Repo.appendIgnoreLine',
      summary: summary,
      skipped: skipped,
      params: {
        'scope': scope.name,
        'target': _shortSource(target.path),
        'stopTracking': stopTracking,
        'rows': rows.length,
        'written': added,
      },
    );
    return summary;
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

  Future<void> _run(
    Future<void> Function() action, {
    required String origin,
    String? command,
  }) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on Exception catch (error) {
      _error = error is GitException ? error.message : error.toString();
      lastFailure = ActionFailure.fromError(
        error,
        origin: origin,
        params: {'cwd': repo.path},
        command: command,
      );
      _busy = false;
      notifyListeners();
      return;
    }
    _busy = false;
    notifyListeners();
    await load();
  }
}

/// One rule the ignore action is about to write.
class _IgnorePlan {
  const _IgnorePlan({required this.row, required this.target, required this.pattern});

  final StatusRow row;
  final IgnoreTarget target;
  final String pattern;
}

/// What one action changed, in the words the UI shows.
class ActionReport {
  const ActionReport({required this.done, this.skipped = const [], this.note});

  /// Rows the action actually changed.
  final int done;

  /// One sentence per row that was left alone, with the reason.
  final List<String> skipped;

  /// Where it happened: the ignore file written, for the ignore actions.
  final String? note;

  /// `tracked 3 files in .gitignore, skipped 1: a.log already there`.
  String message(String verb) {
    final files = done == 1 ? '1 file' : '$done files';
    final where = note == null ? '' : ' in $note';
    final head = done == 0 ? 'nothing changed' : '$verb $files$where';
    if (skipped.isEmpty) return head;
    final more = skipped.length > 3 ? ' (+${skipped.length - 3} more)' : '';
    return '$head, skipped ${skipped.length}: ${skipped.take(3).join('; ')}$more';
  }
}
