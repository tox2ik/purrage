/// The read-only `.gitignore` pane: every ignore file in the repo, its lines,
/// and which line matches the focused path.
///
/// Git reads `.gitignore` at every level, so this is a list of files rather than
/// one file. Nothing here writes: the pane's only actions are opening a file in
/// the editor and asking the caller to create one.
library;

import 'package:flutter/foundation.dart';

import '../timing/ui_timing.dart';
import 'git_repo.dart';
import 'paths.dart';

/// One discovered ignore file, with its lines already split.
class IgnoreFile {
  const IgnoreFile({required this.path, required this.root, required this.lines});

  /// Repo-relative, forward slashes: `.gitignore`, `lib/generated/.gitignore`.
  final String path;

  /// True for the one at the working tree root.
  final bool root;

  final List<String> lines;

  /// A short rail label: `root` for the root file, the folder for a nested one.
  String get label {
    if (root) return '.gitignore';
    const suffix = '/.gitignore';
    return path.endsWith(suffix) ? path.substring(0, path.length - suffix.length) : path;
  }
}

/// A rule that matches the focused path from a file outside the rail.
class OutsideMatch {
  const OutsideMatch({
    required this.pattern,
    required this.line,
    required this.file,
    required this.absolutePath,
  });

  final String pattern;
  final int line;

  /// How the file is named on screen: repo-relative when inside, else absolute.
  final String file;

  /// What "Open" hands to the editor.
  final String absolutePath;

  /// `ignored by `*.log` in .git/info/exclude:3`
  String get sentence => 'ignored by `$pattern` in $file:$line';
}

/// What the pane shows, loaded from [GitRepo] and driven by tests without
/// widgets. Failures become [error]; every method is safe to await.
class IgnorePaneState extends ChangeNotifier {
  IgnorePaneState(this.repo);

  final GitRepo repo;

  List<IgnoreFile> _files = const [];
  String? _selectedPath;
  String? _focusedPath;
  IgnoreMatch? _match;
  String? _error;

  /// Root first, then nested files sorted by path.
  List<IgnoreFile> get files => _files;

  IgnoreFile? get selected =>
      _selectedPath == null ? null : _firstWhere(_files, _selectedPath!);

  String get selectedText => selected?.lines.join('\n') ?? '';

  /// The repo-relative path the pane is explaining, if one was set.
  String? get focusedPath => _focusedPath;

  /// The `check-ignore -v` answer for [focusedPath], when there is one.
  IgnoreMatch? get match => _match;

  String? get error => _error;

  /// A match from a file the rail does not list (`.git/info/exclude`, the global
  /// ignore file), for the one-line "ignored by … in …" with an Open button.
  OutsideMatch? get outsideMatch {
    final match = _match;
    if (match == null) return null;
    final relative = _relative(match.source);
    if (relative != null && _firstWhere(_files, relative) != null) return null;
    return OutsideMatch(
      pattern: match.pattern,
      line: match.line,
      file: relative ?? canonicalPath(match.source),
      absolutePath: relative == null ? canonicalPath(match.source) : _absolute(relative),
    );
  }

  /// The pane's one-word answer for the focused path: `not ignored` is said,
  /// never left blank.
  String get verdict {
    final match = _match;
    if (_focusedPath == null) return '';
    if (match == null) return 'not ignored';
    final line = matchLine;
    if (line != null) return 'line $line';
    if (outsideMatch != null) return 'ignored elsewhere';
    return 'matched in ${_relative(match.source)}:${match.line}';
  }

  /// The 1-based line of the match inside the selected file, or null when the
  /// match lives in another file (or there is no match).
  int? get matchLine {
    final match = _match;
    final file = selected;
    if (match == null || file == null) return null;
    if (_relative(match.source) != file.path) return null;
    if (match.line < 1 || match.line > file.lines.length) return null;
    return match.line;
  }

  /// Read every discovered ignore file, keeping the root first.
  Future<void> load() => UiTiming.instance.time('ignorePane.load', _load);

  Future<void> _load() async {
    try {
      final discovered = await repo.gitignoreFiles();
      final paths = <String>{};
      for (final path in discovered) {
        final clean = _relative(path);
        if (clean != null && clean.isNotEmpty) paths.add(clean);
      }
      final loaded = <IgnoreFile>[];
      for (final path in paths) {
        loaded.add(await _read(path));
      }
      loaded.sort(_rootFirst);
      _files = loaded;
      _keepSelection();
      _error = null;
    } catch (error) {
      _files = const [];
      _selectedPath = null;
      _error = _message(error);
    }
    notifyListeners();
  }

  /// Explain [repoRelativePath] against the ignore files, and select the file
  /// the matching rule lives in, unless the user picked a file for this path.
  ///
  /// The shell starts this from a timer without awaiting it, so the probe is
  /// kept and [idle] can wait for it.
  Future<void> focusPath(String repoRelativePath) {
    final probe = UiTiming.instance.time('ignorePane.focus', () => _focusPath(repoRelativePath));
    _probes.add(probe);
    return probe.whenComplete(() => _probes.remove(probe));
  }

  final Set<Future<void>> _probes = {};
  bool _disposed = false;

  /// Completes when no `check-ignore` probe is running.
  Future<void> idle() async {
    while (_probes.isNotEmpty) {
      await Future.wait([..._probes]);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _focusPath(String repoRelativePath) async {
    if (_focusedPath == repoRelativePath && _match != null) return;
    // The cursor moved on: a pick made for the old path no longer holds.
    if (_focusedPath != repoRelativePath) _pickedFor = null;
    _focusedPath = repoRelativePath;
    try {
      _match = await repo.checkIgnore(repoRelativePath);
      _error = null;
      _followMatch();
    } catch (error) {
      _match = null;
      _error = _message(error);
    }
    notifyListeners();
  }

  /// j / k in the rail: the next or previous file, clamped. A keyboard pick
  /// is the user's own, like a click.
  void selectBy(int delta) {
    if (_files.isEmpty) return;
    final at = _files.indexWhere((file) => file.path == _selectedPath);
    final next = ((at < 0 ? 0 : at) + delta).clamp(0, _files.length - 1);
    pick(_files[next].path);
  }

  /// The rail file the match is in becomes the selection: the pane answers
  /// "why is this ignored" without the user hunting for the right file.
  void _followMatch() {
    final match = _match;
    if (match == null || _pickedFor == _focusedPath) return;
    final relative = _relative(match.source);
    if (relative != null && _firstWhere(_files, relative) != null) _selectedPath = relative;
  }

  /// Select a file from code (a new file, a reload).
  void select(String path) {
    final clean = _relative(path) ?? path;
    if (_selectedPath == clean) return;
    _selectedPath = clean;
    notifyListeners();
  }

  /// The user clicked a file in the rail: that wins over the match until the
  /// cursor moves to another path.
  void pick(String path) {
    _pickedFor = _focusedPath;
    select(path);
  }

  /// The focused path when the user last picked a file by hand.
  String? _pickedFor;

  /// Keep the selected file across a reload when it still exists, else take the
  /// first entry (the root file), else nothing.
  void _keepSelection() {
    if (_selectedPath != null && _firstWhere(_files, _selectedPath!) != null) return;
    _selectedPath = _files.isEmpty ? null : _files.first.path;
  }

  Future<IgnoreFile> _read(String path) async {
    final text = await repo.readTextFile(_absolute(path));
    return IgnoreFile(path: path, root: path == '.gitignore', lines: _split(text));
  }

  static IgnoreFile? _firstWhere(List<IgnoreFile> files, String path) {
    for (final file in files) {
      if (file.path == path) return file;
    }
    return null;
  }

  static int _rootFirst(IgnoreFile a, IgnoreFile b) {
    if (a.root != b.root) return a.root ? -1 : 1;
    return a.path.compareTo(b.path);
  }

  static List<String> _split(String text) {
    if (text.isEmpty) return const [];
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  /// A path as git prints it, made repo-relative and forward-slashed. Null when
  /// it is absolute and outside the repository.
  String? _relative(String path) {
    var clean = canonicalPath(path);
    final root = canonicalPath(repo.path);
    if (clean.toLowerCase().startsWith('${root.toLowerCase()}/')) {
      clean = clean.substring(root.length + 1);
    } else if (clean.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(clean)) {
      return null;
    }
    while (clean.startsWith('./')) {
      clean = clean.substring(2);
    }
    return clean;
  }

  String _absolute(String path) => pathIn(repo.path, path);

  static String _message(Object error) => error is GitException ? error.message : error.toString();
}
