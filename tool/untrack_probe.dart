// ignore_for_file: avoid_print
// Reproduces the nested-repository untrack without the app or the test runner:
// an outer repo holds an embedded git repo, whose staged content differs from
// both HEAD and the working tree, so `git rm --cached` refuses without -f.
//
//   dart run tool/untrack_probe.dart
//
// Prints the command that finally ran and whether the folder survived on disk.
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('purrage_untrack_');
  try {
    final outer = Directory('${root.path}/outer')..createSync();
    final inner = Directory('${outer.path}/inner')..createSync();
    await _git(outer, ['init', '-q', '-b', 'main']);
    await _git(outer, ['config', 'user.email', 'a@b.c']);
    await _git(outer, ['config', 'user.name', 't']);
    await _git(inner, ['init', '-q', '-b', 'main']);
    await _git(inner, ['config', 'user.email', 'a@b.c']);
    await _git(inner, ['config', 'user.name', 't']);
    File('${inner.path}/a.txt').writeAsStringSync('one');
    await _git(inner, ['add', '-A']);
    await _git(inner, ['commit', '-qm', 'one']);
    await _git(outer, ['add', 'inner']);
    await _git(outer, ['commit', '-qm', 'add inner']);
    File('${inner.path}/a.txt').writeAsStringSync('two');
    await _git(inner, ['add', '-A']);
    await _git(inner, ['commit', '-qm', 'two']);
    await _git(outer, ['add', 'inner']);

    final repo = await Repo.open(outer.path);
    try {
      await repo.untrack('inner');
      print('untrack: ok');
      print('command: ${repo.lastCommand}');
      print('index entries left: '
          '${(await _git(outer, ['ls-files', '--stage'])).trim()}');
      print('inner still on disk: ${Directory('${inner.path}/.git').existsSync()}');
    } catch (error) {
      print('untrack: FAILED');
      print('$error');
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<String> _git(Directory dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir.path);
  if (result.exitCode != 0 && !args.contains('rm')) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
  return (result.stdout as String);
}
