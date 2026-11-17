import 'dart:convert';
import 'dart:io';

import 'package:git/git.dart';

import 'git_repo.dart';
import 'status.dart';

/// The one door to git. Everything shelling out happens here.
///
/// `GitDir` (the `git` package) owns repository discovery and the process
/// plumbing. Status is the exception: its `-z` output is raw bytes and the
/// package decodes with the system encoding, which mangles non-ASCII paths, so
/// this class decodes it as UTF-8 itself. That is the only place the app starts
/// a git process without the package.
class Repo implements GitRepo {
  Repo._(this.dir);

  final GitDir dir;

  /// Absolute path of the working tree root, with forward slashes.
  @override
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
    } on GitException catch (error) {
      // A submodule or a nested repository: its staged content matches neither
      // HEAD nor the working tree, so git insists on -f. With --cached that only
      // drops the index entry; the file or folder stays on disk.
      if (!error.message.contains('use -f to force removal')) rethrow;
      await _git(['rm', '--cached', '-f', '--', path]);
    }
  }

  /// Commit the index with one summary line.
  @override
  Future<void> commit(String summary) async {
    await _git(['commit', '-m', summary]);
  }


  /// The rule that ignores [path], if any: `null` when nothing matches.
  @override
  Future<IgnoreMatch?> checkIgnore(String path) async {
    final result = await _git(
      ['check-ignore', '-v', '--', path],
      throwOnError: false,
    );
    if (result.exitCode != 0) return null;
    return IgnoreMatch.parse((result.stdout as String).trim());
  }

  /// Paths inside the repository, for the `.gitignore` list.
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
    final found = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
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

  /// Write [text] to [file], getting past the Windows Hidden attribute.
  ///
  /// Windows refuses `CreateFileW(..., CREATE_ALWAYS)` with ERROR_ACCESS_DENIED
  /// when the existing file carries Hidden (or System), which is why overwriting
  /// a dot file kept in the hidden style fails with `errno 5`. The fast path is
  /// a plain write; only a refusal costs the `attrib` round trip. A cleared
  /// attribute is always put back, including when the second write fails. This is
  /// the same repair `~/AppData/Local/nvim/plugin/hidden-write.lua` does.
  Future<void> writeTextFile(File file, String text) async {
    try {
      await file.writeAsString(text);
      return;
    } on FileSystemException catch (error) {
      if (!Platform.isWindows || error.osError?.errorCode != 5) rethrow;
      final restore = await clearHiddenAndSystem(file.path);
      try {
        await file.writeAsString(text);
      } finally {
        await restore();
      }
    }
  }

  /// Clear Hidden and System on [path]; returns the call that sets them again.
  ///
  /// Throws [GitException] with the manual command when they cannot be cleared:
  /// a write that would silently lose the attribute is not worth having.
  Future<Future<void> Function()> clearHiddenAndSystem(String path) async {
    final flags = await _attributes(path);
    final toRestore = [
      if (flags.contains('H')) 'H',
      if (flags.contains('S')) 'S',
    ];
    if (toRestore.isEmpty) {
      throw GitException('cannot write $path: access denied, and the file is '
          'not Hidden or System (is it read-only, or open elsewhere?)');
    }
    final cleared = await _attrib(['-H', '-S', path]);
    if (!cleared) {
      throw GitException('$path is Hidden, so Windows refuses the write, and '
          '`attrib -H -S` failed. Run:  attrib -H -S "$path"');
    }
    final after = await _attributes(path);
    if (after.contains('H') || after.contains('S')) {
      throw GitException('$path is still Hidden or System after `attrib -H -S`. '
          'Run:  attrib -H -S "$path"');
    }
    return () async {
      final ok = await _attrib([for (final flag in toRestore) '+$flag', path]);
      if (!ok) {
        throw GitException('could not set ${toRestore.join(' and ')} again on '
            '$path. Run:  attrib ${toRestore.map((flag) => '+$flag').join(' ')} "$path"');
      }
    };
  }

  /// The attribute letters `attrib` prints for [path], e.g. `A H`.
  ///
  /// The output is fixed-width flags followed by the path (`A    H        C:\…`),
  /// so the letters are read from the head of the line, up to the path itself.
  Future<Set<String>> _attributes(String path) async {
    final result = await Process.run('attrib', [path]);
    if (result.exitCode != 0) return {};
    final text = result.stdout as String;
    final pathAt = text.toUpperCase().indexOf(path.toUpperCase());
    final head = pathAt > 0 ? text.substring(0, pathAt) : text;
    return {
      for (final rune in head.runes)
        if (String.fromCharCode(rune).toUpperCase() != String.fromCharCode(rune).toLowerCase())
          String.fromCharCode(rune),
    };
  }

  Future<bool> _attrib(List<String> args) async {
    final result = await Process.run('attrib', args);
    return result.exitCode == 0;
  }
}

