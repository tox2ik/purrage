import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';

import 'status.dart';

/// A failure worth showing to the user, with git's own words kept.
class GitException implements Exception {
  GitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The one door to git. Everything shelling out happens here.
///
/// `GitDir` (the `git` package) owns repository discovery and the process
/// plumbing. Status is the exception: its `-z` output is raw bytes and the
/// package decodes with the system encoding, which mangles non-ASCII paths, so
/// this class decodes it as UTF-8 itself. That is the only place the app starts
/// a git process without the package.
class Repo {
  Repo._(this.dir);

  final GitDir dir;

  /// Absolute path of the working tree root, with forward slashes.
  String get path => dir.path;

  static Future<Repo> open(String path) async {
    try {
      final dir = await GitDir.fromExisting(path, allowSubdirectory: true);
      return Repo._(dir);
    } on ProcessException catch (error) {
      throw GitException('git could not be started: ${error.message}');
    } on Exception catch (error) {
      throw GitException('not a git repository: $path\n$error');
    }
  }

  Future<ProcessResult> _git(List<String> args, {bool throwOnError = true}) =>
      dir.runCommand(args, throwOnError: throwOnError);

  /// True when there is nothing to stage, change or list.
  Future<bool> isClean() async {
    final rows = await status();
    return rows.isEmpty;
  }

  Future<List<StatusRow>> status() async {
    final result = await Process.run(
      'git',
      const [
        '--no-optional-locks',
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
        '--find-renames',
      ],
      workingDirectory: path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw GitException('git status failed:\n${result.stderr}');
    }
    return parseStatusZ(result.stdout as String);
  }

  /// Stage a whole file, or a deletion when the file is gone.
  Future<void> track(Iterable<String> paths) async {
    if (paths.isEmpty) return;
    await _git(['add', '--', ...paths]);
  }

  /// Stop tracking a path but leave it on disk.
  Future<void> untrack(String path) async {
    await _git(['rm', '--cached', '--', path]);
  }

  /// Commit the index with one summary line.
  Future<void> commit(String summary) async {
    await _git(['commit', '-m', summary]);
  }

  /// The rule that ignores [path], if any: `null` when nothing matches.
  Future<IgnoreMatch?> checkIgnore(String path) async {
    final result = await _git(
      ['check-ignore', '-v', '--', path],
      throwOnError: false,
    );
    if (result.exitCode != 0) return null;
    return IgnoreMatch.parse((result.stdout as String).trim());
  }

  /// Paths inside the repository, for the `.gitignore` list.
  Future<List<String>> gitignoreFiles() async {
    final result = await _git([
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      ':(glob)**/.gitignore',
    ]);
    final found = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return found;
  }

  /// `.git/info/exclude` for this repository, resolved through git so worktrees
  /// and submodules land on the right file.
  Future<String> localExcludePath() async {
    final result = await _git(['rev-parse', '--git-path', 'info/exclude']);
    var out = (result.stdout as String).trim();
    if (out.isEmpty) out = '.git/info/exclude';
    final absolute = out.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(out)
        ? out
        : '$path/$out';
    return absolute.replaceAll(r'\', '/');
  }

  /// The global ignore file: `core.excludesFile`, else `~/.config/git/ignore`.
  Future<String> globalIgnorePath() async {
    final result = await _git(['config', '--get', 'core.excludesFile'], throwOnError: false);
    final configured = (result.stdout as String).trim();
    if (configured.isNotEmpty) return _expandHome(configured).replaceAll(r'\', '/');
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdg == null || xdg.isEmpty) ? '$home/.config' : xdg;
    return '$base/git/ignore'.replaceAll(r'\', '/');
  }

  static String _expandHome(String path) {
    if (!path.startsWith('~')) return path;
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    return '$home${path.substring(1)}';
  }

  /// Text of an ignore file, or an empty string when it does not exist yet.
  Future<String> readTextFile(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Append one rule to an ignore file, keeping its line endings and leaving one
  /// blank line before the new rule. A rule already present is left alone.
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async {
    final file = File(absolutePath);
    final existing = await readTextFile(absolutePath);
    final present = existing
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .any((line) => line == pattern);
    if (present) return IgnoreAppend.duplicate;

    final eol = existing.contains('\r\n') ? '\r\n' : '\n';
    final buffer = StringBuffer(existing);
    if (existing.isEmpty) {
      buffer.write('# Glustered$eol');
    } else if (existing.endsWith('\n')) {
      buffer.write(eol);
    } else {
      buffer.write(eol);
      buffer.write(eol);
    }
    buffer.write('$pattern$eol');
    await file.parent.create(recursive: true);
    await file.writeAsString(buffer.toString());
    return IgnoreAppend.added;
  }
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
