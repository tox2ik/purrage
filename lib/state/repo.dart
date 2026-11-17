import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';

import 'git_repo.dart';
import 'hidden_write.dart';
import 'paths.dart';
import 'status.dart';
import 'system.dart';

/// The one door to git. Everything shelling out happens here.
///
/// `GitDir` (the `git` package) owns repository discovery and the process
/// plumbing. Status is the exception: its `-z` output is raw bytes and the
/// package decodes with the system encoding, which mangles non-ASCII paths, so
/// this class decodes it as UTF-8 itself. That is the only place the app starts
/// a git process without the package.
class Repo implements GitRepo {
  Repo._(this.dir, {required this.runner, required this.env})
      : hidden = HiddenWrite(runner: runner, isWindows: env.isWindows);

  final GitDir dir;

  /// Status and `attrib` go through this; the rest of git through [dir].
  final ProcessRunner runner;

  /// `USERPROFILE`, `HOME`, `XDG_CONFIG_HOME` for the global ignore file.
  final Env env;

  /// The Hidden/System repair for dot files.
  final HiddenWrite hidden;

  /// Absolute path of the working tree root, with forward slashes.
  @override
  String get path => dir.path;

  /// Open the repository at [path].
  ///
  /// The catch is deliberately `Object`, not `Exception`: `GitDir.fromExisting`
  /// throws an `ArgumentError` for a directory it does not accept, and an `Error`
  /// would otherwise escape past every `on Exception` guard and land in the zone
  /// handler as an uncaught exception.
  static Future<Repo> open(
    String path, {
    ProcessRunner runner = const SystemProcessRunner(),
    Env? env,
  }) async {
    try {
      final dir = await GitDir.fromExisting(path, allowSubdirectory: true);
      return Repo._(dir, runner: runner, env: env ?? Env.system());
    } on ProcessException catch (error) {
      throw GitException('git could not be started: ${error.message}');
    } catch (error) {
      throw GitException('not a git repository: $path\n$error');
    }
  }

  @override
  String? lastCommand;

  Future<ProcessResult> _git(List<String> args, {bool throwOnError = true}) {
    lastCommand = 'git ${args.join(' ')}';
    return dir.runCommand(args, throwOnError: throwOnError);
  }

  /// True when there is nothing to stage, change or list.
  Future<bool> isClean() async {
    final rows = await status();
    return rows.isEmpty;
  }

  @override
  Future<List<StatusRow>> status() async {
    final result = await runner.run(
      'git',
      const [
        '--no-optional-locks',
        'status',
        '--porcelain=v1',
        '-z',
        '--untracked-files=all',
        '--find-renames',
      ],
      cwd: path,
      encoding: utf8,
    );
    if (!result.ok) {
      throw GitException('git status failed:\n${result.stderr}');
    }
    return parseStatusZ(result.stdout);
  }

  /// Stage a whole file, or a deletion when the file is gone.
  @override
  Future<void> track(Iterable<String> paths) async {
    if (paths.isEmpty) return;
    await _git(['add', '--', ...paths]);
  }

  /// Stop tracking a path but leave it on disk.
  @override
  Future<void> untrack(String path) async {
    try {
      await _git(['rm', '--cached', '--', path]);
    } on Object catch (error) {
      // The `git` package throws ProcessException, our own code throws
      // GitException: match on the text, which is what actually says why.
      final text = '$error'.toLowerCase();
      final needsForce = text.contains('use -f') || text.contains('force removal');
      if (!needsForce) rethrow;
      // A submodule or a nested repository: its staged content matches neither
      // HEAD nor the working tree, so git insists on -f. With --cached that only
      // drops the index entry; the file or folder stays on disk.
      await _git(['rm', '--cached', '-f', '--', path]);
    }
  }

  /// Commit the index with one summary line.
  @override
  Future<void> commit(String summary) async {
    await _git(['commit', '-m', summary]);
  }


  /// The rule that ignores [path], if any: `null` when nothing matches.
  ///
  /// The path is passed without a trailing slash on purpose: `git check-ignore`
  /// on a directory written as `dir/` answers with an empty pattern and the last
  /// line it scanned, i.e. claims a match that does not exist. `dir` answers
  /// honestly, which is what the row's path is anyway.
  @override
  Future<IgnoreMatch?> checkIgnore(String path) async {
    final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final result = await _git(
      ['check-ignore', '-v', '--', clean],
      throwOnError: false,
    );
    if (result.exitCode != 0) return null;
    return IgnoreMatch.parse((result.stdout as String).trim());
  }

  /// Paths inside the repository, for the `.gitignore` list.
  @override
  /// Every `.gitignore` in the working tree, repo-relative.
  ///
  /// `ls-files --cached` keeps listing a tracked file after it is deleted from
  /// disk, and `--others` only sees untracked ones: the list is therefore filtered
  /// against the filesystem, or the pane would show a file the user just removed.
  @override
  Future<List<String>> gitignoreFiles() async {
    final result = await _git([
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      ':(glob)**/.gitignore',
    ]);
    final listed = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    final found = <String>[];
    for (final path in listed) {
      if (await File(pathIn(this.path, path)).exists()) found.add(path);
    }
    return found;
  }

  /// `.git/info/exclude` for this repository, resolved through git so worktrees
  /// and submodules land on the right file.
  @override
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
  @override
  Future<String> globalIgnorePath() async {
    final result = await _git(['config', '--get', 'core.excludesFile'], throwOnError: false);
    final configured = (result.stdout as String).trim();
    return globalIgnoreFrom(configured, env);
  }

  /// `core.excludesFile` with `~` expanded, else `$XDG_CONFIG_HOME/git/ignore`,
  /// else `<home>/.config/git/ignore`; forward slashes.
  static String globalIgnoreFrom(String configured, Env env) {
    final home = env.home ?? '';
    if (configured.isNotEmpty) {
      final expanded =
          configured.startsWith('~') ? '$home${configured.substring(1)}' : configured;
      return expanded.replaceAll(r'\', '/');
    }
    final base = env['XDG_CONFIG_HOME'] ?? '$home/.config';
    return '$base/git/ignore'.replaceAll(r'\', '/');
  }

  /// Text of an ignore file, or an empty string when it does not exist yet.
  @override
  Future<String> readTextFile(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Append one rule to an ignore file, keeping its line endings and leaving one
  /// blank line before the new rule. A rule already present is left alone.
  @override
  Future<IgnoreAppend> appendIgnoreLine(String absolutePath, String pattern) async {    final file = File(absolutePath);
    final existing = await readTextFile(absolutePath);
    final present = existing
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .any((line) => line == pattern);
    if (present) return IgnoreAppend.duplicate;

    final eol = existing.contains('\r\n') ? '\r\n' : '\n';
    final buffer = StringBuffer(existing);
    if (existing.isEmpty) {
      buffer.write('# Purrage$eol');
    } else if (!existing.endsWith('\n')) {
      buffer.write(eol);
    }
    buffer.write('$pattern$eol');
    await file.parent.create(recursive: true);
    await writeTextFile(file, buffer.toString());
    return IgnoreAppend.added;
  }

  /// Create an ignore file that is not there yet, with the Purrage header.
  @override
  Future<void> createIgnoreFile(String absolutePath) async {
    final file = File(absolutePath);
    if (await file.exists()) return;
    await file.parent.create(recursive: true);
    await writeTextFile(file, '# Purrage\n');
  }

  /// A `.git` of its own, file or folder, makes the path a repository: an
  /// embedded repo, a gitlink or a submodule. One stat per row that can be one.
  @override
  Future<bool> isNestedRepository(String path) async {
    final clean = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (clean.isEmpty) return false;
    final gitDir = hostPaths.join(canonicalPath(path), '.git');
    final kind = await FileSystemEntity.type(gitDir);
    return kind != FileSystemEntityType.notFound;
  }

  /// `git ls-files -s -z`, keeping the mode-160000 entries.
  @override
  Future<Set<String>> gitlinks() async {
    final result = await _git(['ls-files', '-s', '-z'], throwOnError: false);
    if (result.exitCode != 0) return {};
    final out = result.stdout as String;
    final found = <String>{};
    for (final record in out.split('\u0000')) {
      if (!record.startsWith('160000 ')) continue;
      final tab = record.indexOf('\t');
      if (tab >= 0 && tab + 1 < record.length) found.add(record.substring(tab + 1));
    }
    return found;
  }

  /// Write [text] to [file], getting past the Windows Hidden attribute (see
  /// [HiddenWrite]).
  Future<void> writeTextFile(File file, String text) => hidden.write(file, text);

  /// Clear Hidden and System on [path]; returns the call that sets them again.
  Future<Future<void> Function()> clearHiddenAndSystem(String path) =>
      hidden.clearHiddenAndSystem(path);
}

