import 'package:flutter/foundation.dart';

import 'ignore_rules.dart';
import 'repo.dart';
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

  final Repo repo;

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

  /// The rows the actions work on: the selection, or the cursor row.
  List<StatusRow> get actionRows {
    final chosen = selectedRows;
    if (chosen.isNotEmpty) return chosen;
    final row = selected;
    return row == null ? const [] : [row];
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

  /// Stage every selected file, or its deletion when it is gone.
  Future<void> trackSelected() => _run(() async {
        final paths = actionRows.where((row) => !row.isConflict).map((row) => row.path).toList();
        await repo.track(paths);
      });

  /// Stop tracking the selected files, leaving them on disk.
  Future<void> untrackSelected() => _run(() async {
        final rows = actionRows.where((row) => !row.isConflict && row.section != Section.untracked);
        for (final row in rows) {
          await repo.untrack(row.path);
        }
      });

  /// Commit the index with one summary line.
  Future<bool> commit(String summary) async {
    final message = summary.trim();
    if (message.isEmpty || !canCommit) return false;
    await _run(() => repo.commit(message));
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

  /// Write an ignore rule for every row the action covers.
  ///
  /// Returns null when all rules were written, or a sentence listing what was
  /// skipped and why — a rule that would never match must not be added silently.
  Future<String?> ignoreSelected({
    required IgnoreScope scope,
    required IgnoreTarget target,
    bool stopTracking = false,
  }) async {
    final rows = actionRows;
    if (rows.isEmpty) return 'nothing selected';
    final skipped = <String>[];
    var added = 0;
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
      final appended = await repo.appendIgnoreLine(rowTarget.path, pattern);
      if (appended == IgnoreAppend.duplicate) {
        skipped.add('${row.path}: `$pattern` already there');
        continue;
      }
      if (stopTracking) {
        try {
          await repo.untrack(row.path);
        } on GitException catch (error) {
          skipped.add('${row.path}: ${error.message}');
        }
      }
      added++;
    }
    await load();
    if (skipped.isEmpty) return null;
    final head = skipped.take(3).join('; ');
    final more = skipped.length > 3 ? ' (+${skipped.length - 3} more)' : '';
    return 'ignored $added, skipped ${skipped.length}: $head$more';
  }

  String _shortSource(String path) {
    final repoPath = repo.path.replaceAll(r'\', '/');
    final clean = path.replaceAll(r'\', '/');
    return clean.startsWith('$repoPath/') ? clean.substring(repoPath.length + 1) : clean;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on GitException catch (error) {
      _error = error.message;
      _busy = false;
      notifyListeners();
      return;
    }
    _busy = false;
    notifyListeners();
    await load();
  }
}
