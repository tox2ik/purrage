import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/status.dart';

/// A repository that answers from memory, for widget tests: no git, no files, no
/// real clock. Everything a test asserts about is recorded in [writes].
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

  /// Every method called, in order.
  final List<String> calls = [];

  void _enter(String method) {
    calls.add(method);
    final failure = failures[method];
    if (failure != null) throw failure;
  }

  @override
  Future<List<StatusRow>> status() async {
    _enter('status');
    return rows;
  }

  @override
  Future<void> track(Iterable<String> paths) async {
    _enter('track');
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
  Future<void> untrack(String path) async {
    _enter('untrack');
    lastCommand = 'git rm --cached -- $path';
    rows = [
      for (final row in rows)
        if (row.path != path) row,
    ];
  }

  @override
  Future<void> commit(String summary) async {
    _enter('commit');
    commits.add(summary);
    rows = const [];
  }

  /// Every summary committed.
  final List<String> commits = [];

  /// Paths a test says are already ignored, with the rule that does it.
  final Map<String, IgnoreMatch> ignored = {};

  @override
  Future<IgnoreMatch?> checkIgnore(String path) async {
    _enter('checkIgnore');
    return ignored[path];
  }

  @override
  Future<List<String>> gitignoreFiles() async {
    _enter('gitignoreFiles');
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
    _enter('appendIgnoreLine');
    writes.add('$absolutePath|$pattern');
    files[absolutePath] = '${files[absolutePath] ?? ''}$pattern\n';
    rows = [
      for (final row in rows)
        if (pattern != '/${row.path}') row,
    ];
    return IgnoreAppend.added;
  }

  @override
  Future<bool> isNestedRepository(String path) async => nested.contains(path);

  @override
  Future<Set<String>> gitlinks() async => {...nested};

  /// Paths a test says hold their own repository.
  final Set<String> nested = {};

  @override
  Future<void> createIgnoreFile(String absolutePath) async {
    _enter('createIgnoreFile');
    files.putIfAbsent(absolutePath, () => '# Purrage\n');
  }
}
