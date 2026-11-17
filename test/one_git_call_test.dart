import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/ignore_rules.dart';
import 'package:purrage/state/status.dart';

import 'support/fake_repo.dart';

StatusRow row(String path, Section section) => StatusRow(
      section: section,
      kind: section == Section.untracked ? RowKind.untracked : RowKind.modified,
      path: path,
      code: section == Section.untracked ? '??' : 'M ',
    );

Future<Changes> loaded(FakeRepo repo) async {
  final changes = Changes(repo);
  addTearDown(changes.dispose);
  await changes.load();
  await changes.idle();
  repo.calls.clear();
  return changes;
}

Future<void> selectAll(Changes changes) async {
  await changes.click(0);
  await changes.click(changes.visible.length - 1, shift: true);
}

void main() {
  test('untracking 300 rows is one untrack call', () async {
    final repo = FakeRepo([for (var i = 0; i < 300; i++) row('src/f$i.dart', Section.staged)]);
    final changes = await loaded(repo);
    await selectAll(changes);

    expect((await changes.untrackSelected()).ok, isTrue);
    expect(repo.count('untrack'), 1);
    expect(changes.visible, isEmpty);
  });

  test('ignoring 300 rows is one check-ignore and one write of the file', () async {
    final repo = FakeRepo([for (var i = 0; i < 300; i++) row('src/f$i.log', Section.untracked)]);
    final changes = await loaded(repo);
    await selectAll(changes);

    expect((await changes.ignoreQuick()).ok, isTrue);
    expect(repo.count('checkIgnoreAll'), 1);
    expect(repo.count('checkIgnore'), 0);
    expect(repo.count('appendIgnoreLines'), 1);
    expect(repo.count('appendIgnoreLine'), 0);
    expect(repo.writes, hasLength(300));
  });

  test('rows already ignored are skipped by the one check, the rest are written', () async {
    final repo = FakeRepo([
      row('a.log', Section.untracked),
      row('b.log', Section.untracked),
      row('c.txt', Section.untracked),
    ]);
    repo.ignored['b.log'] = const IgnoreMatch(
      source: 'C:/repo/.gitignore',
      line: 4,
      pattern: '*.log',
      path: 'b.log',
    );
    final changes = await loaded(repo);
    await selectAll(changes);

    final result = await changes.ignoreQuick();
    expect(result.problem, contains('b.log: `*.log` in .gitignore:4'));
    expect(repo.count('checkIgnoreAll'), 1);
    expect(repo.writes, ['C:/repo/.gitignore|/a.log', 'C:/repo/.gitignore|/c.txt']);
  });

  test('a folder target writes each folder file once', () async {
    final repo = FakeRepo([
      for (var i = 0; i < 5; i++) row('one/f$i.tmp', Section.untracked),
      for (var i = 0; i < 5; i++) row('two/f$i.tmp', Section.untracked),
    ]);
    final changes = await loaded(repo);
    await selectAll(changes);
    const folder = IgnoreTarget(
      kind: IgnoreTargetKind.folderGitignore,
      label: 'one',
      path: 'C:/repo/one/.gitignore',
      dir: 'one',
      exists: false,
    );

    await changes.ignoreSelected(scope: IgnoreScope.file, target: folder);
    expect(repo.count('checkIgnoreAll'), 1);
    expect(repo.count('appendIgnoreLines'), 2);
    expect(repo.files.keys, unorderedEquals(['C:/repo/one/.gitignore', 'C:/repo/two/.gitignore']));
  });

  test('ignore with stop tracking untracks the tracked rows in one call', () async {
    final repo = FakeRepo([
      for (var i = 0; i < 4; i++) row('t$i.cfg', Section.staged),
      row('u.cfg', Section.untracked),
    ]);
    final changes = await loaded(repo);
    await selectAll(changes);

    await changes.ignoreSelected(
      scope: IgnoreScope.file,
      target: changes.rootTarget,
      stopTracking: true,
    );
    expect(repo.count('untrack'), 1);
    expect(repo.lastCommand, isNot(contains('u.cfg')));
  });

  test('a row whose rule cannot be written comes back, the others stay gone', () async {
    final repo = FakeRepo([
      row('one/a.tmp', Section.untracked),
      row('two/b.tmp', Section.untracked),
    ]);
    final changes = await loaded(repo);
    await selectAll(changes);
    repo.failures['appendIgnoreLines'] = GitException('disk says no');
    const folder = IgnoreTarget(
      kind: IgnoreTargetKind.folderGitignore,
      label: 'one',
      path: 'C:/repo/one/.gitignore',
      dir: 'one',
      exists: false,
    );

    final result = await changes.ignoreSelected(scope: IgnoreScope.file, target: folder);
    expect(result.ok, isFalse);
    expect(result.problem, contains('disk says no'));
    expect(changes.visible.map((r) => r.path), containsAll(['one/a.tmp', 'two/b.tmp']));
  });
}
