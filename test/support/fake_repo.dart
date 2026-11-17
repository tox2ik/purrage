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

  @override
  Future<List<StatusRow>> status() async => rows;

  @override
  Future<void> track(Iterable<String> paths) async {
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
    lastCommand = 'git rm --cached -- $path';
    rows = [
      for (final row in rows)
        if (row.path != path) row,
    ];
  }

  @override
  Future<void> commit(String summary) async {
    rows = const [];
  }


  @override
  Future<IgnoreMatch?> checkIgnore(String path) async => null;

  @override
  Future<List<String>> gitignoreFiles() async => ['.gitignore'];

  @override
  Future<String> localExcludePath() async => '$path/.git/info/exclude';

  @override
  Future<String> globalIgnorePath() async => 'C:/home/.config/git/ignore';

  @override
  Future<String> readTextFile(String absolutePath) async => files[absolutePath] ?? '';

  @override
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async {
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
    files.putIfAbsent(absolutePath, () => '# Purrage\n');
  }
}
