/// The git surface the app uses.
///
/// `Repo` is the real one; tests supply a fake, which is why the UI can be driven
/// without a repository, a subprocess or a real clock.
library;

import 'status.dart';

/// A failure worth showing to the user, with git's own words kept.
class GitException implements Exception {
  GitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What appending a rule did.
enum IgnoreAppend { added, duplicate }

/// One line of `git check-ignore -v`: the file, the line, and the pattern that
/// decided it.
class IgnoreMatch {
  const IgnoreMatch({
    required this.source,
    required this.line,
    required this.pattern,
    required this.path,
  });

  final String source;
  final int line;
  final String pattern;
  final String path;

  /// `<source>:<line>:<pattern>\t<path>`
  static IgnoreMatch? parse(String raw) {
    if (raw.isEmpty) return null;
    final tab = raw.indexOf('\t');
    final head = tab < 0 ? raw : raw.substring(0, tab);
    final path = tab < 0 ? '' : raw.substring(tab + 1);
    final first = head.indexOf(':');
    final second = first < 0 ? -1 : head.indexOf(':', first + 1);
    if (first < 0 || second < 0) return null;
    return IgnoreMatch(
      source: head.substring(0, first),
      line: int.tryParse(head.substring(first + 1, second)) ?? 0,
      pattern: head.substring(second + 1),
      path: path,
    );
  }
}

/// Everything the app needs from a repository.
abstract class GitRepo {
  /// Absolute path of the working tree root, with forward slashes.
  String get path;

  Future<List<StatusRow>> status();

  /// Stage whole files, or their deletions when they are gone.
  Future<void> track(Iterable<String> paths);

  /// Stop tracking a path but leave it on disk.
  Future<void> untrack(String path);

  /// Commit the index with one summary line.
  Future<void> commit(String summary);

  /// True while a merge is in progress; a commit must wait for it.
  Future<bool> mergeInProgress();

  /// The rule that ignores [path], if any.
  Future<IgnoreMatch?> checkIgnore(String path);

  /// Every `.gitignore` in the working tree, repo-relative.
  Future<List<String>> gitignoreFiles();

  /// `.git/info/exclude` for this repository.
  Future<String> localExcludePath();

  /// The global ignore file.
  Future<String> globalIgnorePath();

  /// Text of a file, or an empty string when it does not exist.
  Future<String> readTextFile(String absolutePath);

  /// Append one rule to an ignore file.
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern);

  /// Create an empty ignore file with the Glustered header, if it is not there.
  Future<void> createIgnoreFile(String absolutePath);
}
