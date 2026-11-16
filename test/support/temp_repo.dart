import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A throwaway repository for one test, deleted when the test ends.
///
/// Everything a test starts or writes goes through here, so a run leaves no
/// `purrage_*` folder behind.
class TempRepo {
  TempRepo._(this.dir);

  final Directory dir;

  String get path => dir.path.replaceAll(r'\', '/');

  static Future<TempRepo> make({bool withGitignore = true}) async {
    final dir = await Directory.systemTemp.createTemp('purrage_');
    final repo = TempRepo._(dir);
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await repo.git(['init', '-b', 'main']);
    await repo.git(['config', 'user.email', 'test@example.com']);
    await repo.git(['config', 'user.name', 'test']);
    await repo.git(['config', 'core.fsmonitor', 'false']);
    if (withGitignore) {
      await repo.write('.gitignore', 'build/\n');
      await repo.git(['add', '.gitignore']);
      await repo.git(['commit', '-m', 'create: initial']);
    }
    return repo;
  }

  Future<ProcessResult> git(List<String> args) async {
    final result = await Process.run(
      'git',
      ['-c', 'core.fsmonitor=false', ...args],
      workingDirectory: dir.path,
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
    }
    return result;
  }

  Future<File> write(String relative, String content) async {
    final file = File('${dir.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }
}

/// True when the temp folder still holds `purrage_*` folders, for the
/// cleanup check in CLAUDE.md.
Future<int> leftoverTempDirs() async {
  var count = 0;
  await for (final entity in Directory.systemTemp.list()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    if (name.startsWith('purrage_')) count++;
  }
  return count;
}
