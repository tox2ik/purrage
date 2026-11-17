import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/git_repo.dart';
import 'package:purrage/state/ignore_rules.dart';
import 'package:purrage/state/status.dart';
import 'package:purrage/state/workspace.dart';

import 'support/fake_repo.dart';
import 'support/fake_system.dart';
import 'support/fake_workspace.dart';

StatusRow untracked(String path) =>
    StatusRow(section: Section.untracked, kind: RowKind.untracked, path: path, code: '??');

StatusRow staged(String path) =>
    StatusRow(section: Section.staged, kind: RowKind.added, path: path, code: 'A ');

/// A started workspace over [rows], disposed when the test ends.
Future<(Workspace, FakeRepo)> started(
  List<StatusRow> rows, {
  RepoOpener? opener,
  FakeRunner? runner,
  Map<String, String> which = const {},
  MemoryPrefs? prefs,
}) async {
  final repo = FakeRepo(rows);
  final workspace = fakeWorkspace(
    repo,
    opener: opener,
    runner: runner,
    which: which,
    prefs: prefs,
    probeDelay: Duration.zero,
  );
  addTearDown(workspace.dispose);
  await workspace.start();
  await workspace.idle();
  return (workspace, repo);
}

/// The newest console row's summary and whether it is a failure.
(String, bool) lastRow(Workspace workspace) {
  final entry = workspace.console.entries.first;
  return (entry.failure.summary, entry.failure.error);
}

void main() {
  group('start and reload', () {
    test('start loads the rows, the ignore files and the saved editor', () async {
      final (workspace, repo) = await started(
        [untracked('a.txt')],
        prefs: MemoryPrefs('nvim {file}'),
      );
      expect(workspace.changes.visible.single.path, 'a.txt');
      expect(workspace.ignorePane.files.single.path, '.gitignore');
      expect(workspace.editorCommand, 'nvim {file}');
      expect(workspace.console.entries.any((entry) => entry.action == 'reload'), isTrue);
      expect(workspace.notices.current, isNull);
    });

    test('reloadAll picks up what git says now', () async {
      final (workspace, repo) = await started([untracked('a.txt')]);
      repo.rows = [untracked('a.txt'), untracked('b.txt')];
      await workspace.reloadAll();
      expect(workspace.changes.visible.map((row) => row.path), ['a.txt', 'b.txt']);
      expect(lastRow(workspace).$1, contains('2 row(s)'));
    });

    test('a resting cursor asks the ignore pane about its row', () async {
      final (workspace, repo) = await started([untracked('a.txt'), untracked('b.txt')]);
      await workspace.changes.move(1);
      await Future<void>.delayed(Duration.zero);
      await workspace.idle();
      expect(workspace.ignorePane.focusedPath, 'b.txt');
    });
  });

  group('open', () {
    test('success swaps the repository, the list and the pane, and says so in the console', () async {
      final other = FakeRepo([untracked('z.txt')], path: 'C:/other');
      final (workspace, _) = await started([untracked('a.txt')], opener: (path) async => other);
      final before = workspace.changes;
      var redraws = 0;
      workspace.addListener(() => redraws++);

      await workspace.open('C:/other');

      expect(workspace.repo, same(other));
      expect(workspace.changes, isNot(same(before)));
      expect(workspace.changes.visible.single.path, 'z.txt');
      expect(workspace.ignorePane.repo, same(other));
      expect(redraws, greaterThan(0));
      expect(lastRow(workspace), ('opened C:/other', false));
      expect(workspace.notices.current, isNull);
      await workspace.idle();
    });

    test('a failure is a notice, and the old repository stays', () async {
      final (workspace, repo) = await started(
        [untracked('a.txt')],
        opener: (path) async => throw GitException('not a git repository: $path'),
      );
      await workspace.open('C:/nope');
      expect(workspace.repo, same(repo));
      expect(workspace.notices.current?.message, 'cannot open C:/nope');
      expect(lastRow(workspace).$2, isTrue);
      expect(workspace.console.entries.first.failure.detail, contains('not a git repository'));
    });

    test('a seeded workspace refuses to switch, out loud', () async {
      final (workspace, repo) = await started([untracked('a.txt')]);
      await workspace.open('C:/other');
      expect(workspace.repo, same(repo));
      expect(workspace.notices.current?.message, contains('seeded'));
    });
  });

  group('row actions', () {
    test('track: a success is a console row, no notice', () async {
      final (workspace, repo) = await started([untracked('a.txt')]);
      await workspace.track();
      expect(repo.rows.single.section, Section.staged);
      expect(lastRow(workspace), ('tracked 1 file', false));
      expect(workspace.console.entries.first.failure.detail, contains('command: git add -- a.txt'));
      expect(workspace.notices.current, isNull);
    });

    test('track: a failure is said, and the row goes back', () async {
      final (workspace, repo) = await started([untracked('a.txt')]);
      repo.failures['track'] = GitException('index.lock exists');
      await workspace.track();
      expect(workspace.changes.visible.single.section, Section.untracked);
      expect(workspace.notices.current?.message, contains('could not stage'));
      expect(lastRow(workspace).$2, isTrue);
    });

    test('untrack: success and failure', () async {
      final (workspace, repo) = await started([staged('a.txt')]);
      repo.failures['untrack'] = GitException('pathspec did not match');
      await workspace.untrack();
      expect(workspace.notices.current?.message, contains('could not stop tracking'));
      expect(workspace.changes.visible.single.path, 'a.txt');

      repo.failures.clear();
      await workspace.untrack();
      expect(lastRow(workspace), ('stopped tracking 1 file', false));
    });

    test('ignoreQuick writes the literal rule and reloads the pane', () async {
      final (workspace, repo) = await started([untracked('notes.md')]);
      await workspace.ignoreQuick();
      expect(repo.writes.single, 'C:/repo/.gitignore|/notes.md');
      expect(lastRow(workspace), ('ignored 1 file', false));
      expect(workspace.ignorePane.files.single.lines, contains('/notes.md'));
    });

    test('ignoreQuick: an already ignored row is a refusal that names the rule', () async {
      final (workspace, repo) = await started([untracked('es/x/')]);
      repo.ignored['es/x/'] = const IgnoreMatch(
        source: 'C:/repo/.gitignore',
        line: 135,
        pattern: '/es/',
        path: 'es/x',
      );
      await workspace.ignoreQuick();
      expect(repo.writes, isEmpty);
      expect(workspace.notices.current?.message, contains('`/es/` in .gitignore:135'));
    });

    test('an exception inside an action becomes a notice, not a crash', () async {
      final (workspace, repo) = await started([untracked('notes.md')]);
      repo.failures['checkIgnore'] = GitException('git died');
      await workspace.ignoreQuick();
      expect(workspace.notices.current?.message, 'ignore failed');
    });

    test('the dialog flow: the question, then the chosen rule', () async {
      final (workspace, repo) = await started([untracked('lib/a.log')]);
      final question = await workspace.ignoreQuestion();
      expect(question!.row.path, 'lib/a.log');
      final root = question.targets.firstWhere((t) => t.kind == IgnoreTargetKind.rootGitignore);
      await workspace.ignore(scope: IgnoreScope.extension, target: root);
      expect(repo.writes.single, 'C:/repo/.gitignore|*.log');
      expect(lastRow(workspace), ('ignored 1 file', false));
    });

    test('no question without a row, and a failing lookup is said', () async {
      final (workspace, repo) = await started(const []);
      expect(await workspace.ignoreQuestion(), isNull);
      expect(workspace.notices.current?.message, 'nothing selected to ignore');

      repo.rows = [untracked('a.txt')];
      await workspace.reloadAll();
      repo.failures['gitignoreFiles'] = GitException('ls-files failed');
      expect(await workspace.ignoreQuestion(), isNull);
      expect(workspace.notices.current?.message, 'ignore failed');
    });
  });

  group('commit', () {
    test('a commit is reported, a refused one is said', () async {
      final (workspace, repo) = await started([staged('a.txt')]);
      expect(await workspace.commit('add a'), isTrue);
      expect(repo.commits, ['add a']);
      expect(lastRow(workspace).$1, startsWith('commit'));

      expect(await workspace.commit('again'), isFalse, reason: 'nothing staged any more');
      expect(workspace.notices.current?.message, 'nothing is staged');
    });

    test('a git failure is said with git\'s words', () async {
      final (workspace, repo) = await started([staged('a.txt')]);
      repo.failures['commit'] = GitException('hook refused');
      expect(await workspace.commit('add a'), isFalse);
      expect(workspace.notices.current?.message, 'hook refused');
    });
  });

  group('editor', () {
    test('openFocused starts the chosen editor on the file', () async {
      final runner = FakeRunner();
      final (workspace, _) = await started(
        [untracked('a.txt')],
        runner: runner,
        which: {'code': r'C:\bin\code.exe'},
      );
      await workspace.openFocused();
      expect(runner.calls.single.line, r'C:\bin\code.exe C:/repo/a.txt');
      expect(workspace.notices.current, isNull);
    });

    test('a folder, nothing selected, or a failed start are said', () async {
      final runner = FakeRunner((_) => null);
      final (workspace, repo) = await started([untracked('dir/')], runner: runner);
      await workspace.openFocused();
      expect(workspace.notices.current?.message, 'dir/ is a folder');

      await workspace.openSelectedIgnore();
      expect(workspace.notices.current?.message, contains('Could not start Notepad'));

      repo.rows = const [];
      await workspace.reloadAll();
      await workspace.openFocused();
      expect(workspace.notices.current?.message, 'nothing selected to open');
    });

    test('the Test button and the editor choice', () async {
      final runner = FakeRunner();
      final prefs = MemoryPrefs();
      final (workspace, _) = await started(const [], runner: runner, prefs: prefs);
      await workspace.chooseEditor('"C:/x/ed.exe" {file}');
      expect(prefs.saved, '"C:/x/ed.exe" {file}');
      expect(workspace.editorCommand, '"C:/x/ed.exe" {file}');
      await workspace.openTestFile('PLAN.md');
      expect(runner.calls.single.line, 'C:/x/ed.exe C:/repo/PLAN.md');
    });
  });

  group('new ignore here', () {
    test('creates the file in the row\'s folder and selects it', () async {
      final (workspace, repo) = await started([untracked('assets/raw/pic.psd')]);
      await workspace.newIgnoreHere();
      expect(repo.files.keys, contains('C:/repo/assets/raw/.gitignore'));
      expect(workspace.ignorePane.focusedPath, 'assets/raw/pic.psd');
      expect(workspace.notices.current, isNull);
    });

    test('a failure or no row is said', () async {
      final (workspace, repo) = await started([untracked('a.txt')]);
      repo.failures['createIgnoreFile'] = GitException('access denied');
      await workspace.newIgnoreHere();
      expect(workspace.notices.current?.message, 'could not create .gitignore');

      repo.rows = const [];
      await workspace.reloadAll();
      await workspace.newIgnoreHere();
      expect(workspace.notices.current?.message, 'nothing selected');
    });
  });
}
