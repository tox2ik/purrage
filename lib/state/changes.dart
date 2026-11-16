import 'package:flutter/foundation.dart';

import 'repo.dart';
import 'status.dart';

/// The state of the Changes mode: what git says, which row is focused, what the
/// preview shows, and the actions that change the index.
///
/// Everything the UI needs to decide is here, so tests drive this class without
/// widgets.
class Changes extends ChangeNotifier {
  Changes(this.repo);

  final Repo repo;

  List<StatusRow> _rows = const [];
  int _index = 0;
  bool _busy = false;
  String? _error;
  FilePreview? _preview;
  String? _previewPath;

  List<StatusRow> get rows => _rows;
  int get index => _index;
  bool get busy => _busy;
  String? get error => _error;
  FilePreview? get preview => _preview;
  String? get previewPath => _previewPath;

  StatusRow? get selected => _rows.isEmpty ? null : _rows[_index];

  /// Rows of one section, in display order.
  List<StatusRow> section(Section section) =>
      _rows.where((row) => row.section == section).toList();

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
      _index = _indexAfterReload(keepPath);
      _error = null;
    } on GitException catch (error) {
      _error = error.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
    await _loadPreview();
  }

  int _indexAfterReload(String? keepPath) {
    if (_rows.isEmpty) return 0;
    if (keepPath == null) return _index.clamp(0, _rows.length - 1);
    final found = _rows.indexWhere((row) => row.path == keepPath);
    if (found >= 0) return found;
    return _index.clamp(0, _rows.length - 1);
  }

  static int _compare(StatusRow a, StatusRow b) {
    final bySection = a.section.index.compareTo(b.section.index);
    return bySection != 0 ? bySection : a.path.compareTo(b.path);
  }

  /// Move the cursor by [delta] rows, staying inside the list.
  Future<void> move(int delta) async {
    if (_rows.isEmpty) return;
    final next = (_index + delta).clamp(0, _rows.length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
    await _loadPreview();
  }

  Future<void> select(int index) async {
    if (_rows.isEmpty) return;
    final next = index.clamp(0, _rows.length - 1);
    if (next == _index) return;
    _index = next;
    notifyListeners();
    await _loadPreview();
  }

  Future<void> _loadPreview() async {
    final row = selected;
    if (row == null || row.path.endsWith('/')) {
      _preview = null;
      _previewPath = null;
      notifyListeners();
      return;
    }
    final path = row.path;
    _previewPath = path;
    final loaded = await repo.preview(path);
    // A slower read must not overwrite the newer selection's preview.
    if (_previewPath != path) return;
    _preview = loaded;
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
