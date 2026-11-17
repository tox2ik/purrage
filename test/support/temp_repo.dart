import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/repo.dart';

import 'temp_dirs.dart';

/// A throwaway repository for one test, deleted when the test ends.
///
/// Everything a test starts or writes goes through here, so a run leaves no
/// `purrage_*` folder behind.
class TempRepo {
  TempRepo._(this.dir);

  final Directory dir;

  String get path => dir.path.replaceAll(r'\', '/');

  /// Teardowns run last-registered first, so the delete registered here runs
  /// after a test's own `addTearDown(changes.idle)`: the background git work is
  /// over before the folder goes. A folder still locked after the retries is
  /// left to `flutter_test_config.dart`, which fails the file over it.
  static Future<TempRepo> make({bool withGitignore = true}) async {
    final dir = keepForCleanup(await Directory.systemTemp.createTemp('purrage_'));
    final repo = TempRepo._(dir);
    addTearDown(() => deleteWithRetry(dir));
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

  /// A repository of its own at [relative] inside [outer]; it goes away with
  /// the outer one.
  static Future<TempRepo> nested(TempRepo outer, String relative) async {
    final dir = Directory('${outer.dir.path}/$relative');
    await dir.create(recursive: true);
    final repo = TempRepo._(dir);
    await repo.git(['init', '-q', '-b', 'main']);
    await repo.git(['config', 'user.email', 'test@example.com']);
    await repo.git(['config', 'user.name', 'test']);
    await repo.git(['config', 'core.fsmonitor', 'false']);
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

  /// A [Changes] over this repository whose background work (the nested probe)
  /// the test waits for before the folder is deleted.
  Future<Changes> changes() async => watch(Changes(await Repo.open(path)));

  Future<File> write(String relative, String content) async {
    final file = File('${dir.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }
}

/// Register [changes] so the test's teardown waits for its background work. The
/// teardown is registered after [TempRepo.make]'s delete, so it runs first.
Changes watch(Changes changes) {
  addTearDown(changes.idle);
  return changes;
}
