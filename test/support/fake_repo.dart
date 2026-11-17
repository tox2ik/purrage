import 'dart:async';

import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/status.dart';

/// A repository that answers from memory, for widget tests: no git, no files, no
/// real clock. Everything a test asserts about is recorded in [writes] and
/// [calls].
class FakeRepo implements GitRepo {
  FakeRepo(this.rows, {this.path = 'C:/repo'});

  List<StatusRow> rows;

  @override
  String? lastCommand;

  @override
  final String path;

  /// `'<file>| <pattern>'` per accepted rule.
  final List<String> writes = [];

  final Map<String, String> files = {};

  /// Calls that throw instead of answering, by method name (`track`,
  /// `untrack`, `commit`, `status`, `createIgnoreFile`, ...).
  final Map<String, Object> failures = {};

  /// Every method called, in order: what would be one git process (or one
  /// file write) each in the real repository.
  final List<String> calls = [];

  /// How often [method] was called.
  int count(String method) => calls.where((call) => call == method).length;

  /// Calls held open until the test completes the completer: `complete()`
  /// lets the call go on, `completeError(e)` fails it with `e`. One hold
  /// holds the next call of that method only.
  final Map<String, Completer<void>> holds = {};

  /// Hold the next call of [method]; the test decides how it ends.
  Completer<void> hold(String method) => holds[method] = Completer<void>();

  Future<void> _enter(String method) async {
    calls.add(method);
    final held = holds.remove(method);
    if (held != null) await held.future;
    final failure = failures[method];
    if (failure != null) throw failure;
  }

  @override
  Future<List<StatusRow>> status() async {
    await _enter('status');
    return rows;
  }

  @override
  Future<void> track(Iterable<String> paths) async {
    await _enter('track');
    final staged = paths.toSet();
    lastCommand = 'git add -- ${paths.join(' ')}';
    rows = [
      for (final row in rows)
        if (staged.contains(row.path))
          StatusRow(
            section: Section.staged,
            kind: row.kind,
            path: row.path,
            code: row.code,
          )
        else
          row,
    ];
  }

  @override
  Future<void> untrack(Iterable<String> paths) async {
    await _enter('untrack');
    final gone = paths.toSet();
    lastCommand = 'git rm --cached -- ${gone.join(' ')}';
    rows = [
      for (final row in rows)
        if (!gone.contains(row.path)) row,
    ];
  }

  /// Every summary committed, in order.
  final List<String> commits = [];

  @override
  Future<void> commit(String summary) async {
    await _enter('commit');
    commits.add(summary);
    rows = const [];
  }

  /// What `currentBranch()` answers; null is a detached HEAD.
  String? branch = 'main';

  @override
  Future<String?> currentBranch() async => branch;


  /// Paths a test says are already ignored, with the rule that does it.
  final Map<String, IgnoreMatch> ignored = {};

  @override
  Future<IgnoreMatch?> checkIgnore(String path) async {
    await _enter('checkIgnore');
    return ignored[path];
  }

  @override
  Future<Map<String, IgnoreMatch>> checkIgnoreAll(Iterable<String> paths) async {
    await _enter('checkIgnoreAll');
    return {
      for (final path in paths)
        if (ignored[path] != null) path: ignored[path]!,
    };
  }

  @override
  Future<List<String>> gitignoreFiles() async {
    await _enter('gitignoreFiles');
    return ['.gitignore'];
  }

  @override
  Future<String> localExcludePath() async => '$path/.git/info/exclude';

  @override
  Future<String> globalIgnorePath() async => 'C:/home/.config/git/ignore';

  @override
  Future<String> readTextFile(String absolutePath) async => files[absolutePath] ?? '';

  @override
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async {
    await _enter('appendIgnoreLine');
    _append(absolutePath, [pattern]);
    return IgnoreAppend.added;
  }

  @override
  Future<List<IgnoreAppend>> appendIgnoreLines(String absolutePath, List<String> patterns) async {
    await _enter('appendIgnoreLines');
    _append(absolutePath, patterns);
    return [for (final _ in patterns) IgnoreAppend.added];
  }

  /// Write every rule (no duplicate check here: the real file does that) and
  /// drop the untracked rows a literal rule names (like git, a rule never hides
  /// a tracked file).
  void _append(String absolutePath, List<String> patterns) {
    for (final pattern in patterns) {
      writes.add('$absolutePath|$pattern');
      files[absolutePath] = '${files[absolutePath] ?? ''}$pattern\n';
    }
    final gone = patterns.toSet();
    rows = [
      for (final row in rows)
        if (!gone.contains('/${row.path}') || row.section != Section.untracked) row,
    ];
  }

  @override
  Future<bool> isNestedRepository(String path) async => nested.contains(path);

  @override
  Future<Set<String>> gitlinks() async => {...nested};

  /// Paths a test says hold their own repository.
  final Set<String> nested = {};

  @override
  Future<void> createIgnoreFile(String absolutePath) async {
    await _enter('createIgnoreFile');
    files.putIfAbsent(absolutePath, () => '# Purrage\n');
  }
}
