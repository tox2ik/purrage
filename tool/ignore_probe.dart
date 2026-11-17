// ignore_for_file: avoid_print
// Proves the ignore flow on an untracked nested repository: git answers such a
// directory with an empty pattern, which used to make the app refuse. Pure Dart
// on purpose (no Flutter imports), so `dart run` works.
//
//   dart run tool/ignore_probe.dart
import 'dart:io';

import 'package:purrage/state/repo.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('purrage_ignore_');
  try {
    final outer = Directory('${root.path}/outer')..createSync();
    final inner = Directory('${outer.path}/es/inner')..createSync(recursive: true);
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
    print('before, git sees: ${await _git(outer, ['status', '--porcelain', '-uall'])}');
    print('check-ignore(es/inner/) -> ${await repo.checkIgnore('es/inner/') ?? 'no match'}');

    final written = await repo.appendIgnoreLine('${outer.path}/.gitignore', '/es/inner/');
    print('append: $written');
    print('after, git sees: ${await _git(outer, ['status', '--porcelain', '-uall'])}');
    print('check-ignore(es/inner/) -> ${await repo.checkIgnore('es/inner/') ?? 'no match'}');
    print('rules now: ${File('${outer.path}/.gitignore').readAsStringSync().replaceAll('\n', '|')}');
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<String> _git(Directory dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir.path);
  return (result.stdout as String).trim();
}
