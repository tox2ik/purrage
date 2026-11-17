// ignore_for_file: avoid_print
// Builds a throwaway outer repository with an untracked nested repository at
// <nested>, then ignores that folder the way the app does and prints what git
// says before and after. Pure Dart on purpose (no Flutter imports), so
// `dart run` works.
//
// Why this exists: git answers `check-ignore` for an untracked nested
// repository with an empty pattern, which made the app refuse the ignore as
// "already ignored" by a rule that does not exist. An empty pattern now counts
// as "no rule" (6f3f52f). `test/repo_test.dart` asserts the same thing; this
// probe prints it step by step.
//
//   dart run tool/ignore_probe.dart <nested>
//
// The folder it was written for:
//
//   dart run tool/ignore_probe.dart es/inner
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    print(
      'usage: dart run tool/ignore_probe.dart <nested folder, e.g. es/inner>',
    );
    exitCode = 64;
    return;
  }
  final nested = args.first.replaceAll(RegExp(r'/+$'), '');
  final root = Directory.systemTemp.createTempSync('purrage_ignore_');
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
    File('${inner.path}/a.txt').writeAsStringSync('x');
    await _git(inner, ['add', '-A']);
    await _git(inner, ['commit', '-qm', 'one']);
    File('${outer.path}/.gitignore').writeAsStringSync('*.log\n\n# keep\n');

    final repo = await Repo.open(outer.path);
    print(
      'before, git sees: ${await _git(outer, ['status', '--porcelain', '-uall'])}',
    );
    print(
      'check-ignore($nested/) -> ${await repo.checkIgnore('$nested/') ?? 'no match'}',
    );

    final written = await repo.appendIgnoreLine(
      '${outer.path}/.gitignore',
      '/$nested/',
    );
    print('append: $written');
    print(
      'after, git sees: ${await _git(outer, ['status', '--porcelain', '-uall'])}',
    );
    print(
      'check-ignore($nested/) -> ${await repo.checkIgnore('$nested/') ?? 'no match'}',
    );
    print(
      'rules now: ${File('${outer.path}/.gitignore').readAsStringSync().replaceAll('\n', '|')}',
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<String> _git(Directory dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir.path);
  return (result.stdout as String).trim();
}
