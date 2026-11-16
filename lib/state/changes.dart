import 'package:flutter/foundation.dart';

import 'ignore_rules.dart';
import 'repo.dart';
import 'status.dart';

/// The state of the Changes mode: what git says, which row is focused, what the
/// and the actions that change the index.
///
/// Everything the UI needs to decide is here, so tests drive this class without
/// widgets.
class Changes extends ChangeNotifier {
  Changes(this.repo);

  final Repo repo;

  List<StatusRow> _rows = const [];
  List<StatusRow> _visible = const [];
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

  StatusRow? get selected => _visible.isEmpty ? null : _visible[_index];

  /// Rows of one section, in display order.
  List<StatusRow> section(Section section) =>
      _visible.where((row) => row.section == section).toList();

  int get stagedCount => _rows.where((row) => row.section == Section.staged).length;

  bool get canCommit => stagedCount > 0 && !_busy;

  /// Reload from git, keeping the selection on the same path when it still exists.
  Future<void> load() async {
    _busy = true;
    notifyListeners();
    final keepPath = selected?.path;
    try {
      final rows = await repo.status();
      _rows = [...rows]..sort(_compare);
      _applyFilter();
      _index = _indexAfterReload(keepPath);
      _error = null;
    } on GitException catch (error) {
      _error = error.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
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

  /// Narrow the list; the cursor goes to the first match.
  Future<void> setFilter(String query) async {
    if (query == _filter) return;
    _filter = query;
    _applyFilter();
    _index = 0;
    notifyListeners();
  }

  void _applyFilter() {
    _visible = filterRows(_rows, _filter);
  }

  /// Move the cursor by [delta] rows, staying inside the list.
  Future<void> move(int delta) async {
    if (_visible.isEmpty) return;
    final next = (_index + delta).clamp(0, _visible.length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }

  Future<void> select(int index) async {
    if (_visible.isEmpty) return;
    final next = index.clamp(0, _visible.length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }

  /// Stage the focused file, or a deletion when it is gone.
  Future<void> trackSelected() => _run(() async {
        final row = selected;
        if (row == null || row.isConflict) return;
        await repo.track([row.path]);
      });

  /// Stop tracking the focused file, leaving it on disk.
  Future<void> untrackSelected() => _run(() async {
        final row = selected;
        if (row == null || row.isConflict) return;
        await repo.untrack(row.path);
      });

  /// Commit the index with one summary line.
  Future<bool> commit(String summary) async {
    final message = summary.trim();
    if (message.isEmpty || !canCommit) return false;
    await _run(() => repo.commit(message));
    return _error == null;
  }

  /// The ignore files to offer for the focused file, narrowest first.
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

  /// Write an ignore rule for the focused file.
  ///
  /// Returns null when it was written, or a sentence explaining why nothing was
  /// written — a rule that would never match must not be added silently.
  Future<String?> ignoreSelected({
    required IgnoreScope scope,
    required IgnoreTarget target,
    bool stopTracking = false,
  }) async {
    final row = selected;
    if (row == null) return 'nothing selected';
    final pattern = IgnoreRules.pattern(scope: scope, targetDir: target.dir, path: row.path);
    if (pattern == null) return 'this scope makes no rule for ${row.name}';

    final existing = await repo.checkIgnore(row.path);
    if (existing != null) {
      final where = '${_shortSource(existing.source)}:${existing.line}';
      return '${row.path} is already ignored by `${existing.pattern}` in $where';
    }

    final appended = await repo.appendIgnoreLine(target.path, pattern);
    if (appended == IgnoreAppend.duplicate) {
      return '`$pattern` is already in ${_shortSource(target.path)}';
    }
    if (stopTracking) {
      await repo.untrack(row.path);
    }
    await load();
    return null;
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
