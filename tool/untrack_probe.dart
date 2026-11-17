// ignore_for_file: avoid_print
// Reproduces the nested-repository untrack without the app or the test runner:
// a throwaway outer repo holds an embedded git repo at <nested>, whose staged
// content differs from both HEAD and the working tree, so `git rm --cached`
// refuses without -f. Prints the command that finally ran and whether the
// folder survived on disk.
//
// Why this exists: untrack failed on nested repositories ("use -f to force
// removal"). The fix retries with `git rm --cached -f`, which only drops the
// index entry and never touches the disk (3be68ca "fix untrack for real").
// `test/repo_test.dart` asserts it, including that the folder is still there.
//
//   dart run tool/untrack_probe.dart <nested>
//
// The folder it was written for:
//
//   dart run tool/untrack_probe.dart inner
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    print(
      'usage: dart run tool/untrack_probe.dart <nested folder, e.g. inner>',
    );
    exitCode = 64;
    return;
  }
  final nested = args.first.replaceAll(RegExp(r'/+$'), '');
  final root = Directory.systemTemp.createTempSync('purrage_untrack_');
  try {
    final outer = Directory('${root.path}/outer')..createSync();
    final inner = Directory('${outer.path}/$nested')
      ..createSync(recursive: true);
    await _git(outer, ['init', '-q', '-b', 'main']);
    await _git(outer, ['config', 'user.email', 'a@b.c']);
    await _git(outer, ['config', 'user.name', 't']);
    await _git(inner, ['init', '-q', '-b', 'main']);
    await _git(inner, ['config', 'user.email', 'a@b.c']);
    await _git(inner, ['config', 'user.name', 't']);
    File('${inner.path}/a.txt').writeAsStringSync('one');
    await _git(inner, ['add', '-A']);
    await _git(inner, ['commit', '-qm', 'one']);
    await _git(outer, ['add', nested]);
    await _git(outer, ['commit', '-qm', 'add $nested']);
    File('${inner.path}/a.txt').writeAsStringSync('two');
    await _git(inner, ['add', '-A']);
    await _git(inner, ['commit', '-qm', 'two']);
    await _git(outer, ['add', nested]);

    final repo = await Repo.open(outer.path);
    try {
      await repo.untrack([nested]);
      print('untrack: ok');
      print('command: ${repo.lastCommand}');
      print(
        'index entries left: '
        '${(await _git(outer, ['ls-files', '--stage'])).trim()}',
      );
      print(
        '$nested still on disk: ${Directory('${inner.path}/.git').existsSync()}',
      );
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
