import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/state/changes.dart';
import 'package:glustered/state/ignore_rules.dart';
import 'package:glustered/state/repo.dart';

import 'support/temp_repo.dart';

/// End-to-end over a real repository: real files, the real `git` binary, the
/// real porcelain output. Nothing here is faked, and each case checks what git
/// itself says afterwards, not only what the app believes.
void main() {
  /// `git check-ignore -v` for a path, or null when git does not ignore it.
  Future<String?> checkedBy(TempRepo temp, String path) async {
    final result = await Process.run(
      'git',
      ['check-ignore', '-v', '--', path],
      workingDirectory: temp.path,
    );
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }

  /// Repo-relative paths git lists as changed.
  Future<List<String>> changed(TempRepo temp) async {
    final result = await temp.git(['status', '--porcelain', '-z', '--untracked-files=all']);
    return [
      for (final record in (result.stdout as String).split('\u0000'))
        if (record.length > 3) record.substring(3),
    ];
  }

  test('quick ignore writes a literal rule that git then honours', () async {
    final temp = await TempRepo.make();
    await temp.write('notes.md', 'scratch\n');
    final changes = Changes(await Repo.open(temp.path));
    await changes.load();

    expect(changes.visible.single.path, 'notes.md');
    expect(await changes.ignoreQuick(), isNull);

    final text = await File('${temp.path}/.gitignore').readAsString();
    expect(text, contains('\n/notes.md\n'));
    expect(await checkedBy(temp, 'notes.md'), contains('.gitignore'));
    expect(await checkedBy(temp, 'notes.md'), contains('/notes.md'));
    expect(await changed(temp), isNot(contains('notes.md')));
    // Changing the ignored file keeps it invisible to git.
    await temp.write('notes.md', 'scratch again\n');
    expect(await changed(temp), isNot(contains('notes.md')));
  });

  test('the dialog target writes into a nested .gitignore, relative to it', () async {
    final temp = await TempRepo.make();
    await temp.write('lib/generated/a.g.dart', 'generated\n');
    final changes = Changes(await Repo.open(temp.path));
    await changes.load();

    final targets = await changes.ignoreTargets();
    final nested = targets.firstWhere((t) => t.kind == IgnoreTargetKind.folderGitignore);
    expect(nested.path, endsWith('lib/generated/.gitignore'));
    expect(nested.path.contains(r'\'), isFalse);

    expect(await changes.ignoreSelected(scope: IgnoreScope.file, target: nested), isNull);

    final nestedFile = File('${temp.path}/lib/generated/.gitignore');
    expect(await nestedFile.exists(), isTrue);
    final text = await nestedFile.readAsString();
    expect(text, startsWith('# Glustered\n'));
    expect(text, contains('\n/a.g.dart\n'));
    expect(text, isNot(contains('lib/generated/a.g.dart'))); // not the root form

    // git agrees, and names the nested file as the source.
    final match = await checkedBy(temp, 'lib/generated/a.g.dart');
    expect(match, contains('lib/generated/.gitignore'));
    expect(match, contains('/a.g.dart'));
    // The root .gitignore was not touched by this rule.
    expect(await File('${temp.path}/.gitignore').readAsString(), 'build/\n');
    // The new .gitignore itself is a change to commit.
    expect(await changed(temp), contains('lib/generated/.gitignore'));
  });

  test('a multi-selection is ignored in one action', () async {
    final temp = await TempRepo.make();
    await temp.write('a.log', '1\n');
    await temp.write('b.log', '2\n');
    await temp.write('keep.txt', '3\n');
    final changes = Changes(await Repo.open(temp.path));
    await changes.load();

    expect(changes.visible.map((row) => row.path), containsAll(['a.log', 'b.log']));
    // Select the two .log rows with Ctrl clicks, the way the list does.
    final first = changes.visible.indexWhere((row) => row.path == 'a.log');
    final second = changes.visible.indexWhere((row) => row.path == 'b.log');
    await changes.click(first);
    await changes.click(second, ctrl: true);
    expect(changes.selectionCount, 2);

    expect(await changes.ignoreQuick(), isNull);

    final text = await File('${temp.path}/.gitignore').readAsString();
    expect(text, contains('\n/a.log\n'));
    expect(text, contains('\n/b.log\n'));
    expect(text, isNot(contains('keep.txt')));
    expect(await checkedBy(temp, 'a.log'), isNotNull);
    expect(await checkedBy(temp, 'b.log'), isNotNull);
    expect(await checkedBy(temp, 'keep.txt'), isNull);
    expect(await changed(temp), contains('keep.txt'));
  });

  test('ignoring a tracked file leaves it tracked until stop-tracking runs', () async {
    final temp = await TempRepo.make();
    await temp.write('keep.txt', 'tracked\n');
    final repo = await Repo.open(temp.path);
    await repo.track(['keep.txt']);
    await repo.commit('add keep');
    await temp.write('keep.txt', 'changed\n');

    final changes = Changes(repo);
    await changes.load();
    expect(changes.visible.single.path, 'keep.txt');
    expect(changes.visible.single.section.name, 'changed');

    final root = changes.rootTarget;
    expect(await changes.ignoreSelected(scope: IgnoreScope.file, target: root), isNull);

    // The rule exists, and git still tracks the file: ignoring alone changes
    // nothing for a tracked path.
    final tracked = await temp.git(['ls-files', '--', 'keep.txt']);
    expect((tracked.stdout as String).trim(), 'keep.txt');
    // Our own check-ignore guard sees it as ignored, while git status still
    // reports the modification, because tracked files ignore rules do not apply.
    expect(await changed(temp), contains('keep.txt'));
  });

  test('stop tracking makes the ignored file disappear from status', () async {
    final temp = await TempRepo.make();
    await temp.write('junk.bin', 'x\n');
    final repo = await Repo.open(temp.path);
    await repo.track(['junk.bin']);
    await repo.commit('add junk');
    await temp.write('junk.bin', 'y\n');

    final changes = Changes(repo);
    await changes.load();
    final root = changes.rootTarget;
    expect(
      await changes.ignoreSelected(scope: IgnoreScope.file, target: root, stopTracking: true),
      isNull,
    );

    final tracked = await temp.git(['ls-files', '--', 'junk.bin']);
    expect((tracked.stdout as String).trim(), isEmpty);
    expect(await File('${temp.path}/junk.bin').exists(), isTrue);
    // The index change is a staged deletion (`D `), and nothing more: git would
    // not quietly drop a tracked file without one.
    final status = await temp.git(['status', '--porcelain', '--', 'junk.bin']);
    expect((status.stdout as String).trim(), 'D  junk.bin');
    expect(await checkedBy(temp, 'junk.bin'), contains('/junk.bin'));
  });

  test('New here creates a .gitignore that git then reads', () async {
    final temp = await TempRepo.make();
    await temp.write('assets/raw/pic.psd', 'binary\n');
    final repo = await Repo.open(temp.path);
    await repo.createIgnoreFile('${temp.path}/assets/raw/.gitignore');
    await repo.appendIgnoreLine('${temp.path}/assets/raw/.gitignore', '/pic.psd');

    expect(await checkedBy(temp, 'assets/raw/pic.psd'), contains('assets/raw/.gitignore'));
    expect(await changed(temp), isNot(contains('assets/raw/pic.psd')));

    // And the pane's discovery finds both files, root first.
    expect(await repo.gitignoreFiles(), containsAll(['assets/raw/.gitignore', '.gitignore']));
  });

  test('a name with glob characters is escaped and still matches itself', () async {
    final temp = await TempRepo.make();
    await temp.write('odd[1].txt', 'x\n');
    await temp.write('odd1.txt', 'x\n');
    final changes = Changes(await Repo.open(temp.path));
    await changes.load();

    final first = changes.visible.indexWhere((row) => row.path == 'odd[1].txt');
    await changes.click(first);
    expect(await changes.ignoreQuick(), isNull);

    final text = await File('${temp.path}/.gitignore').readAsString();
    expect(text, contains(r'/odd\[1\].txt'));
    // The literal file is ignored; the file that a raw glob would have caught is not.
    expect(await checkedBy(temp, 'odd[1].txt'), isNotNull);
    expect(await checkedBy(temp, 'odd1.txt'), isNull);
  });
}
