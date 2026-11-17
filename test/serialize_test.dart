import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/status.dart';

import 'support/fake_repo.dart';

StatusRow untracked(String path) =>
    StatusRow(section: Section.untracked, kind: RowKind.untracked, path: path, code: '??');

/// Put the cursor (and the selection) on [path].
Future<void> pick(Changes changes, String path) =>
    changes.click(changes.visible.indexWhere((row) => row.path == path));

String where(Changes changes, String path) =>
    changes.visible.where((row) => row.path == path).map((row) => row.section.name).join(',');

void main() {
  test('a failed track takes back its own row only: the ignored row stays gone', () async {
    final repo = FakeRepo([untracked('a.txt'), untracked('b.log')]);
    final changes = Changes(repo);
    await changes.load();

    final held = repo.hold('track');
    await pick(changes, 'a.txt');
    final track = changes.trackSelected();
    expect(where(changes, 'a.txt'), 'staged', reason: 'optimistic: the row moves at once');

    await pick(changes, 'b.log');
    final ignore = changes.ignoreQuick();
    await pumpEventQueue();
    expect(where(changes, 'b.log'), '', reason: 'the ignored row leaves at once');
    expect(repo.calls, isNot(contains('appendIgnoreLine')), reason: 'git waits for the track');

    held.completeError(GitException('index.lock exists'));
    final tracked = await track;
    expect(tracked.ok, isFalse);
    expect(where(changes, 'a.txt'), 'untracked', reason: 'its own change is undone');
    expect(where(changes, 'b.log'), '', reason: 'the other action is left alone');

    final ignored = await ignore;
    expect(ignored.ok, isTrue);
    expect(repo.writes.single, 'C:/repo/.gitignore|/b.log');
    expect(changes.visible.map((row) => row.path), ['a.txt']);
  });

  test('each action returns its own result, whatever ran in between', () async {
    final repo = FakeRepo([untracked('a.txt'), untracked('b.log')]);
    final changes = Changes(repo);
    await changes.load();

    final held = repo.hold('track');
    await pick(changes, 'a.txt');
    final track = changes.trackSelected();
    await pick(changes, 'b.log');
    final ignore = changes.ignoreQuick();
    held.complete();

    final (tracked, ignored) = (await track, await ignore);
    expect(tracked.action, 'track');
    expect(tracked.command, 'git add -- a.txt');
    expect(tracked.origin, contains('Repo.track'));
    expect(tracked.changed, 1);
    expect(ignored.action, 'ignore');
    expect(ignored.command, '.gitignore += /b.log');
    expect(ignored.origin, contains('appendIgnoreLine'));
  });

  test('git steps run in order, and only the last one re-reads status', () async {
    final repo = FakeRepo([untracked('a.txt'), untracked('b.txt'), untracked('c.txt')]);
    final changes = Changes(repo);
    await changes.load();
    repo.calls.clear();

    final held = repo.hold('track');
    await pick(changes, 'a.txt');
    final first = changes.trackSelected();
    await pick(changes, 'b.txt');
    final second = changes.trackSelected();
    held.complete();
    await Future.wait([first, second]);

    expect(repo.calls, ['track', 'track', 'status']);
    expect(changes.visible.where((row) => row.isStaged).map((row) => row.path), ['a.txt', 'b.txt']);
  });

  test('a failed untrack brings back exactly its rows', () async {
    final repo = FakeRepo([
      StatusRow(section: Section.staged, kind: RowKind.added, path: 'a.txt', code: 'A '),
      untracked('b.txt'),
    ]);
    final changes = Changes(repo);
    await changes.load();
    repo.failures['untrack'] = GitException('pathspec did not match');

    await pick(changes, 'a.txt');
    final result = await changes.untrackSelected();
    expect(result.ok, isFalse);
    expect(result.failure!.summary, 'could not stop tracking 1 file(s)');
    expect(where(changes, 'a.txt'), 'staged');
  });

  test('a commit waits for the queue and reports itself', () async {
    final repo = FakeRepo([untracked('a.txt')]);
    final changes = Changes(repo);
    await changes.load();
    final held = repo.hold('track');
    final track = changes.trackSelected();
    final commit = changes.commit('add a');
    expect(changes.busy, isTrue);
    await pumpEventQueue();
    expect(repo.commits, isEmpty, reason: 'the commit is behind the track');
    held.complete();
    await track;
    final result = await commit;
    expect(result.ok, isTrue);
    expect(result.command, 'git commit -m add a');
    expect(repo.commits, ['add a']);
    expect(changes.busy, isFalse);
  });

  test('refusals say why without touching git', () async {
    final repo = FakeRepo(const []);
    final changes = Changes(repo);
    await changes.load();
    repo.calls.clear();
    expect((await changes.trackSelected()).problem, 'nothing selected');
    expect((await changes.untrackSelected()).problem, 'nothing to stop tracking');
    expect((await changes.ignoreQuick()).problem, 'nothing selected');
    expect((await changes.commit(' ')).problem, 'the summary is empty');
    expect((await changes.commit('x')).problem, 'nothing is staged');
    expect(repo.calls, isEmpty);
  });
}
